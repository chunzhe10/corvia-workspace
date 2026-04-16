# stock-agent v0.1 Design

Date: 2026-04-16
Status: Design approved for implementation
Owner: chunzhe10
Working name: `stock-agent` (final name TBD)

A custom-built LLM agent that runs nightly on a US stock + ETF watchlist, gathers and investigates material events using Gemini Flash on the free tier, writes structured research packs to corvia, and exposes them to Claude via MCP for query-side reasoning. The portfolio anchor is the explicit cost-quality split: cheap collection, expensive reasoning.

## 0. Why this document exists

This is the design output of a brainstorming session that reconciled several earlier research docs in `docs/llm-research/`:

- [2026-04-14-portfolio-strategy-ai-engineer.md](2026-04-14-portfolio-strategy-ai-engineer.md)
- [2026-04-15-malaysia-agent-builder-reeval.md](2026-04-15-malaysia-agent-builder-reeval.md)
- [2026-04-15-domain-selection-job-vs-stocks.md](2026-04-15-domain-selection-job-vs-stocks.md)
- [2026-04-15-sota-financial-research-agents.md](2026-04-15-sota-financial-research-agents.md)

It supersedes the architecture sketches in those docs where they conflict with what is below.

## 1. Goals

1. Ship a working autonomous research agent for a US stock + ETF watchlist in two weeks
2. Demonstrate "I wrote the agent loop from scratch" without a framework
3. Exploit the cost-quality asymmetry between Gemini Flash (cheap collection) and Claude (expensive reasoning) cleanly enough to be a research contribution
4. Stay strictly on free or already-paid services (Gemini API free tier, Claude Max subscription)
5. Dogfood corvia as the memory layer end-to-end
6. Produce a portfolio artifact strong enough to anchor an AI engineer job hunt in Malaysia

## 2. Non-goals

1. Stock recommendations or trading signals. This is a research note generator, not an advisor.
2. Backtesting or paper trading. Not in scope at any version.
3. Generic agent framework. The harness is purpose-built for this domain.
4. Multi-agent orchestration in v0.1. Single agent loop only. Bull/Bear debate is a v0.3 stretch.
5. PDF parsing of glossy annual reports. v0.3+.
6. Bahasa Malaysia output. v0.3+.
7. Any LangChain / LangGraph / Pydantic-AI / framework imports. Ever. Raw SDK only.
8. Bursa Malaysia coverage. Dropped from this project after the domain pivot. US stocks + ETFs only.

## 3. Architecture

### 3.1 The three processes

```
    ┌──────────────────────┐
    │  Claude (query side) │
    │  Claude Code/Desktop │
    └──────────┬───────────┘
               │
               │ MCP: 5 tools
               │   list_watchlist
               │   get_ticker_context
               │   write_thesis
               │   rerun_ticker
               │   get_run_trace
               ▼
    ┌─────────────────────────────────────┐
    │  stock-agent  (Python package)      │
    │                                     │
    │  Two entry points, one codebase:    │
    │                                     │
    │  $ stock-agent serve                │
    │      Long-lived MCP server          │
    │      Exposes the 5 tools to Claude  │
    │                                     │
    │  $ stock-agent collect [--ticker X] │
    │      Short-lived CLI                │
    │      Runs the collection loop       │
    │      Cron calls this nightly        │
    │                                     │
    │  Shared internals:                  │
    │    • collection function            │
    │      (Phase 1-5, Gemini tools)      │
    │    • corvia MCP client              │
    │    • configuration + watchlist      │
    └──────────────────┬──────────────────┘
                       │
                       │ MCP client
                       │ (corvia_write for packs+theses,
                       │  corvia_search/context for reads)
                       ▼
           ┌─────────────────────┐
           │       corvia        │
           │   (memory + MCP)    │
           └─────────────────────┘
```

Three components, all running locally, all free or already paid.

### 3.2 Module responsibilities

| Module | What it is | Owns | Does not do |
|---|---|---|---|
| `stock-agent` | Python package with two entry points | Collection loop, MCP tool surface, thesis writes, `LLMClient` protocol | Storage (corvia's job), reasoning (Claude's job), data (external sources) |
| `corvia` | Memory server (existing prior work) | Persistence, semantic retrieval, agent identity attribution, MCP facade | Finance knowledge, collection, scheduling |
| `Claude` | Query-side LLM via Claude Code/Desktop | All reasoning, thesis formation, answering user questions | Collection, data fetching, storage |

### 3.3 The seam contract

Eight rules that must hold everywhere. Violations are bugs.

1. **stock-agent is the only MCP server Claude connects to.** One tool surface, one mental model.
2. **stock-agent is the only process that talks to corvia.** Both `collect` and `serve` modes use the shared internal corvia MCP client.
3. **Gemini never reads Claude's output.** Gemini runs inside `collect` mode. Claude runs on the query side. They never share a context.
4. **Claude never reads raw data.** Claude only sees structured packs and prior theses via the 4 stock-agent MCP tools.
5. **Deterministic code owns everything LLMs cannot improve.** Python handles scheduling, XBRL parsing, yfinance fetches, watchlist management, storage dispatch, budget enforcement. No LLM call happens where a function call suffices.
6. **Gemini output is verbatim or factual digest, never opinion.** No "this is bullish," no synthesis, no thesis formation. Enforced in the Phase 4 pack assembly prompt.
7. **Untrusted fetched content is sandboxed.** Any bytes returned by `fetch_url`, `fetch_news_body`, or `web_search` are wrapped in `<untrusted_source>...</untrusted_source>` delimiters when fed back into the thread. The reporter system prompt states that instructions appearing inside those blocks are data, not directives.
8. **All LLM outputs are schema-validated.** Every Gemini phase that expects structured output is parsed against a Pydantic model. Schema failures trigger one retry with the validator error fed back. Second failure logs and skips the phase.

### 3.4 The two data flows

**Nightly collection flow** (no user involvement):

```
cron → stock-agent collect --all
  for each ticker in watchlist.yaml:
    Phase 1 (Python): fetch primary data
    Phase 2 (Gemini, 1 call): triage material events
    Phase 3 (Gemini, iterative tool use): investigate each flagged event
    Phase 4 (Gemini, 1 call): assemble pack from collected facts
    Phase 5 (Gemini, 1 call): relevance-tag investigated threads
    write pack to corvia via MCP (corvia_write)
  exit
```

**Query flow** (user-triggered):

```
user in Claude Code/Desktop: "What is going on with MU?"
Claude calls stock-agent.get_ticker_context("MU")
  serve mode reads corvia: latest pack + last 3 theses
  composes structured response
  returns to Claude
Claude reasons over the pack and prior theses
Claude answers the user
if Claude judges thesis materially changed:
  Claude calls stock-agent.write_thesis("MU", new_prose, change_summary)
  serve mode writes to corvia via MCP (corvia_write)
```

### 3.5 Context flow across phases

What goes into each Gemini call's context window:

```
Phase 2 (Triage, single-shot):
  IN  ← headlines[≤30] + deterministic price/volume anomaly summary
        + filing section index
  OUT → TriageOutput { flagged_events[] }

Phase 3 (Investigate, iterative per event):
  IN  ← reporter system prompt
        + event { label, description }
        + [tool_call, <untrusted_source>tool_result</untrusted_source>]*
          growing thread
  OUT → tool_call | done(reason)

Phase 4 (Assemble, single-shot):
  IN  ← RawCorpus.structured_data + RawCorpus.prose_sections
        + investigated_events[].collected_facts (verbatim)
  OUT → Pack (validated against Pydantic model)

Phase 5 (Review, single-shot):
  IN  ← just-assembled Pack + event labels
  OUT → { event_id: "material" | "marginal" | "unrelated" }
```

Phase 3 is the only phase whose thread grows iteratively. Phases 2, 4, 5 are single-shot. Fetched content only ever enters the window wrapped in `<untrusted_source>` delimiters (rule 7).

## 4. Collection harness internals

The whole agentic work lives here. Five phases. Phase 1 is deterministic Python. Phases 2 through 5 use Gemini.

### 4.1 Phase 1: Primary fetch (deterministic Python, no LLM)

Fetches the raw corpus for one ticker:

- **yfinance** for price history, fundamentals, ratios, financial statements (structured)
- **SEC EDGAR** (via `edgartools` or equivalent) for the last 4 quarterly filings (10-Q, 10-K, 8-K), pulls XBRL structured data and prose sections separately
- **News RSS** from primary sources only: Reuters, Bloomberg tier-2, company IR page, SEC filing feed, PR Newswire for company announcements. Filtered to the last 72 hours.
- **Insider transactions** (SEC Form 4, optional)
- **Institutional holdings** (13F if recent, optional)

Output:

```python
@dataclass
class RawCorpus:
    ticker: str
    fetched_at: datetime
    structured_data: StructuredSnapshot   # yfinance numbers, XBRL facts
    prose_sections: list[ProseSection]    # MD&A, Risk Factors, etc., chunked by section
    news_items: list[NewsItem]            # headlines + URLs, NOT bodies
    insider_transactions: list[InsiderTx]
```

**Important**: news bodies are NOT fetched in Phase 1. Only headlines and URLs. Phase 3 may decide to fetch specific bodies during investigation. This keeps Phase 1 fast and avoids fetching content nothing will need.

Filings are chunked by section so Phase 2 and 3 can request specific sections without reading whole filings.

Everything is cached to disk with a content hash. Re-runs within 6 hours skip already-fetched content.

### 4.2 Phase 2: Triage (one Gemini call)

Input: news headlines, deterministic price/volume anomaly summary, list of available filing sections.

System prompt suffix (full prompt versioned at `prompts/triage_v1.md`):

> You are a financial news reporter. Identify material events from the inputs that would warrant deeper investigation. Material means: a sell-side analyst would plausibly write a note about this. Examples: earnings guidance changes, M&A, material product launches, executive departures, regulatory changes, large customer wins or losses. Skip: minor partnerships, marketing announcements, ESG commitments, routine hires, small acquisitions under 1% of market cap, RSS fluff.

Output (structured JSON):

```json
{
  "flagged_events": [
    {
      "id": "micron-ddr6-launch",
      "label": "Micron announces DDR6 memory",
      "description": "Micron declared first shipment of DDR6 samples, claimed first-mover status",
      "source": "headlines[3]",
      "why_material": "First-mover in new memory cycle, directly relevant to margin and market-share thesis"
    }
  ]
}
```

If Phase 2 returns zero events, Phase 3 is skipped entirely. Phase 4 runs on the raw corpus alone.

Output is parsed against the `TriageOutput` Pydantic model. Schema failure triggers one retry with the validator error fed back; second failure logs and skips the triage step (Phase 4 still runs on the raw corpus).

Budget: 1 call per ticker. Input ~5-8k tokens. Output ~1-2k tokens.

### 4.3 Phase 3: Investigation (iterative Gemini tool use)

This is the agentic loop. Per flagged event:

```python
for event in flagged_events:
    budget = InvestigationBudget(
        max_calls=5,
        max_tokens_in=100_000,
        max_tokens_out=20_000,
        chain_depth_limit=1,
    )
    while not budget.exhausted() and not event.done:
        response = gemini.chat(
            messages=thread_so_far,
            tools=INVESTIGATION_TOOLS,
            system_prompt=REPORTER_SYSTEM_PROMPT,
        )
        if response.stop_reason == "tool_use":
            tool_result = execute_tool(response.tool_call, budget)
            thread_so_far.extend([response, tool_result])
            budget.record_call(response)
        elif response.stop_reason == "end_turn" or response.tool_call.name == "done":
            event.done = True
            event.collected_facts = response.content
```

#### Investigation tools (5 total)

| Tool | Input | Output | Purpose |
|---|---|---|---|
| `web_search(query, max_results=5)` | query string | list of {title, url, snippet} | Find new context on a topic |
| `fetch_url(url, extract="prose")` | URL | verbatim text with source citation | Read a specific page |
| `fetch_filing_section(ticker, filing, section)` | identifiers | verbatim section text | Deep read a filing section already in Phase 1 corpus |
| `fetch_news_body(news_item_id)` | headline ID | verbatim article body | Expand a headline into full text |
| `done(event_id, reason)` | event ID + one-line reason | terminates investigation for this event | Self-termination when enough context gathered |

Tools return verbatim content. Gemini does not paraphrase during retrieval.

Chain depth is enforced at the tool-call level. `web_search` is the only tool that opens a new chain. `fetch_url` on a URL returned from web_search is at depth 1 and cannot trigger another `web_search` for the same event.

All tool calls are logged to the run log with call count, token usage, and outcome.

#### Tool result validation and sandboxing

Every tool result is validated before being fed back to Gemini:

- **Size cap**: 50KB per call. Oversized content is truncated with a `[TRUNCATED — original N bytes]` marker.
- **Content-type check**: `fetch_url` rejects non-text responses (binary, PDF for v0.1) and returns an error result the model can see.
- **Injection sandboxing**: all fetched bytes are wrapped in `<untrusted_source url="…">...</untrusted_source>` delimiters when serialized back into the thread. The reporter system prompt declares that any instructions appearing inside those delimiters are data, not directives. This is the defense against prompt injection via press releases, blog posts, or manipulated news bodies (seam rule 7).
- **Structured results**: each tool has a typed `ToolResult` schema (`stock_agent.models.ToolResult`). Harness validates structure before passing back.

Tool calls that fail validation are recorded as tool errors in the thread so Gemini can self-recover within the event budget.

#### Termination rules

Three conditions, ORed. Any one trips termination for an event:

1. **Hard call cap**: 5 calls per event. Always the final stop.
2. **`done(event, reason)` tool**: Gemini self-terminates when confident.
3. **Zero-return detector** (Python, deterministic): track named entities and numbers across calls. After 2 consecutive calls with zero new facts, force-terminate.

Per-ticker aggregation:
- Max 15 Phase 3 calls per ticker (across all events)
- Max 150k Phase 3 tokens per ticker (soft warning at 80k)
- If a ticker pace-exhausts mid-investigation, remaining events get 0 calls

Global ceiling: if the nightly run hits the 500 RPD Gemini cap, remaining tickers in the watchlist are skipped for this run and logged. Collection resumes the next night.

### 4.4 Phase 4: Pack assembly (one Gemini call)

Input: everything from Phase 1 + everything collected in Phase 3 (verbatim tool call results per investigated event).

System prompt suffix (versioned at `prompts/assembler_v1.md`):

> Assemble a research pack for {ticker}. Include all verbatim facts organized by section. Do not add opinion. Do not synthesize across facts. Do not draw conclusions. Do not write a thesis. Do not say "this is bullish" or "investors will like." Your job is to organize, not interpret.

Output: a structured Pack object (schema below). Parsed against the `Pack` Pydantic model. Schema failure triggers one retry with the validator error fed back; second failure logs, writes a partial `stale_data: true` pack marked `assembly_failed`, and continues.

Budget: 1 call per ticker. Input ~20-40k tokens. Output ~8-15k tokens.

### 4.5 Phase 5: Relevance review (one Gemini call)

Phase 5 is the safety net against Gemini investigation drift. Input: the assembled pack. Output: a relevance tag for each investigated event.

```json
{
  "tags": {
    "micron-ddr6-launch": "material",
    "micron-china-export-mention": "marginal",
    "micron-employee-recognition": "unrelated"
  }
}
```

Applied deterministically in Python:
- `material` → keep all collected facts in pack
- `marginal` → reduce to one summary line + primary source citation
- `unrelated` → drop from pack entirely, log to run report

Output is parsed against the `RelevanceTags` Pydantic model. Schema failure triggers one retry; second failure logs and defaults all events to `marginal` (safe middle ground — kept but deprioritized).

Budget: 1 call per ticker. Input ~15k tokens. Output ~1k tokens.

Phase 5 can be disabled via the `phase_5_enabled` config flag. This is the ablation switch used in the v0.1 micro-eval to measure what the review step actually contributes.

### 4.6 Per-ticker budget summary

Realistic average for a ticker with 1 material event:

| Phase | Calls | Input tokens | Output tokens |
|---|---|---|---|
| 1 (Python) | 0 | 0 | 0 |
| 2 (Gemini) | 1 | ~6k | ~1k |
| 3 (Gemini) | 3-5 | ~30-50k | ~6-8k |
| 4 (Gemini) | 1 | ~25k | ~10k |
| 5 (Gemini) | 1 | ~12k | ~1k |
| **Total** | **6-8** | **~75-95k** | **~18-20k** |

For 10 tickers nightly: ~60-80 Gemini calls per run. ~12-16% of the 500 RPD free tier ceiling. Substantial headroom for debug runs, on-demand reruns, and watchlist growth.

### 4.7 Tunable parameters

These are the values exposed in `config.yaml`. Starting values are theoretical and need calibration after week 1 of operation.

| Parameter | Starting value | Reason | Tuning signal |
|---|---|---|---|
| `max_calls_per_event` | 5 | 3 initial + 2 chain follow-up | Adjust if avg actual is far from 3 |
| `max_calls_per_ticker_phase3` | 15 | 3 events at full budget | Reduce if RPD trips |
| `max_tokens_per_ticker` | 150k hard, 80k soft | Fits free tier comfortably | Lower if individual runs balloon |
| `chain_depth_limit` | 1 | Medium investigation latitude | Drop to 0 if drift is high |
| `zero_return_streak_termination` | 2 | Avoids diminishing returns | Increase to 3 if too aggressive |
| `cache_ttl_hours` | 6 | Skip re-fetching within this window | Adjust if data freshness matters |
| `news_lookback_hours` | 72 | Catches weekend events | Tighten if too noisy |
| `news_max_per_ticker_phase1` | 30 | Caps headline count fed to Phase 2 | Adjust per ticker activity |
| `phase_5_enabled` | true | Ablation toggle for relevance review | Flip to false for Phase 5 ablation studies |

### 4.8 LLM output validation

All Gemini phases that expect structured output define a Pydantic v2 model in `stock_agent/models.py`. The validation flow is identical everywhere:

1. Request Gemini structured output (JSON mode).
2. Parse response against the Pydantic model.
3. On validation failure: retry once with the validation error appended to the prompt suffix ("Your previous output failed validation: {error}. Fix and return valid JSON.").
4. On second failure: log, skip the phase, continue the pipeline. Per-phase fallback behavior is documented in each phase section above.

This gives one-retry self-correction at effectively zero extra cost (the retry prompt is short) and prevents malformed JSON from silently propagating into packs.

### 4.9 Error handling

- **Gemini transient errors** (rate limit, 5xx): exponential backoff, max 3 retries per call, then skip that event and continue.
- **Gemini malformed output** (not JSON when expected, safety filter trip): log, skip event, continue with other events.
- **yfinance / SEC failures**: Phase 1 retries once, then uses stale data from the last successful fetch (cached on disk). Pack is flagged `stale_data: true` in metadata.
- **corvia write failures**: retry 3x, then write the pack to `.stock-agent/staging/<ticker>-<ts>.json` and log an error. A reconciliation script picks up staging files on next run.
- **Whole-run failures**: cron catches exit-nonzero and writes to a daily run log. Status surfaces in `list_watchlist` for the user.

### 4.10 System prompts

Four versioned system prompts. Versioned to make eval comparisons reproducible.

- `prompts/reporter_v1.md`: base reporter persona used in Phases 2, 3, 4. Includes the `<untrusted_source>` sandboxing directive (seam rule 7).
- `prompts/triage_v1.md`: Phase 2 suffix specifying the materiality heuristic
- `prompts/assembler_v1.md`: Phase 4 suffix forbidding opinion and synthesis
- `prompts/reviewer_v1.md`: Phase 5 relevance tagging rubric

The pack records which prompt versions produced it, so eval reruns after prompt changes are clearly attributable.

### 4.11 Prompt regression harness

Versioned prompts need frozen inputs to replay against for regression detection.

**v0.1 scaffolding:**

```
fixtures/
  fixture_mu_20260416.json     # one captured Phase 1 RawCorpus
scripts/
  prompt_regression.py         # (version, fixture) -> output JSON
```

On Day 7, when the first end-to-end pipeline completes, the RawCorpus for one ticker is captured to `fixtures/`. The runner takes a prompt version and fixture, executes the relevant phase, writes output to `results/<version>-<fixture>-<timestamp>.json`.

**v0.2 full harness:** 3-5 fixtures, LLM-as-judge diff grader comparing version pairs, regression passing required before merging a prompt version bump.

## 5. Data model

### 5.1 Pack schema

Stored in corvia2 via `corvia_write` with `kind="reference"`, `tags=["pack", "ticker:MU", "run:run-20260416-0000"]`, `agent_id="stock-agent-collector"`.

Content is a YAML front-matter block followed by markdown-structured sections. This lets structured metadata and prose fit inside corvia's single `content` string field:

```markdown
---
kind: pack
ticker: MU
generated_at: 2026-04-16T00:08:32Z
collection_run_id: run-20260416-0000
data_cutoff: 2026-04-15T23:59:59Z
stale_data: false
prompt_versions:
  reporter: v1
  triage: v1
  assembler: v1
  reviewer: v1
budget_used:
  phase_2_calls: 1
  phase_3_calls: 4
  phase_4_calls: 1
  phase_5_calls: 1
  tokens_in: 67000
  tokens_out: 11000
  est_cost_usd: 0.0023
---

## Structured snapshot

| Metric | Value |
|---|---|
| Close | 105.32 |
| 1D change | -2.1% |
| Market cap | 117.5B |
| PE (TTM) | 18.4 |
| Gross margin (latest Q) | 31.1% |
| Gross margin (prior Q) | 28.7% |
| Revenue growth YoY | 42% |

## Prose extracts

> Demand for high-bandwidth memory continued to exceed supply...
> -- MU 10-Q FY2026 Q2 MD&A, p.28

## Investigated events

### Micron announces DDR6 memory [material]

**Primary source:** [Micron IR](https://investors.micron.com/news/press-release/...)
> Micron Technology, Inc. announced today the first samples of DDR6...
> -- fetched 2026-04-16T00:09:01Z

**Context gathered:**
- JEDEC press release (2026-02-11): "..."
- Samsung newsroom (2026-03-22): "..."

## News digest

- "..." -- Reuters, 2026-04-15
```

The `est_cost_usd` field records the dollar cost at public retail rates for the Gemini calls in this run ($0.00 on free tier, but the at-retail equivalent is tracked for the eval study).

The entire pack is also defined in-memory as a Pydantic v2 `Pack` model (`stock_agent/models.py`). Serialization to the corvia content format is a `Pack.to_corvia_markdown()` method. Deserialization from corvia reads parses the YAML front-matter and markdown back into the model.

### 5.2 Thesis schema

Stored in corvia2 via `corvia_write` with `kind="decision"`, `tags=["thesis", "ticker:MU"]`, `agent_id="stock-agent-claude-query"`, and `supersedes=["<prior_entry_id>"]` (native corvia2 parameter).

```markdown
---
kind: thesis
ticker: MU
written_at: 2026-04-16T08:32:11Z
author: claude-sonnet-4-6
based_on_pack: <pack_entry_id>
change_summary: Adds DDR6 first-mover angle as a timing accelerant
---

Micron is positioned as the clear first-mover in the DDR6 cycle, with JEDEC
ratification fresh and Samsung roughly six months behind on samples. The stated
customer mix points to AI infrastructure buyers, which is where memory pricing
has been strongest. Historically, memory first-mover advantages compress within
2-3 quarters as competitors catch up, so the differentiated window is probably
H2 2026 through Q1 2027. My prior thesis, written 2026-03-28, focused on the
broader DRAM cycle recovery; the DDR6 development strengthens the timing case
without changing the underlying cycle call. Risks: Samsung roadmap could pull
forward, hyperscaler capex could decelerate.
```

Supersession is explicit via the `supersedes` parameter on `corvia_write`, not embedded in the content. corvia2 atomically marks the prior entry as superseded and removes it from search. The full chain is retrievable via `corvia history <thesis_entry_id>`.

### 5.3 Canonical schemas as code

All phase outputs and the Pack/Thesis shapes are defined once in `stock_agent/models.py` as Pydantic v2 models. These are the single source of truth:

- `TriageOutput` -- Phase 2 output (flagged events)
- `ToolResult` -- Phase 3 tool return envelope (source, content, size)
- `Pack` -- Phase 4 output (composed of `StructuredSnapshot`, `ProseExtract`, `InvestigatedEvent`, `BudgetUsed`)
- `RelevanceTags` -- Phase 5 output
- `Thesis` -- query-side thesis written by Claude

Serialization to/from corvia's markdown content format is handled by `to_corvia_markdown()` / `from_corvia_markdown()` methods on `Pack` and `Thesis`.

### 5.4 corvia2 Kind mapping

| stock-agent concept | corvia2 `Kind` | Rationale |
|---|---|---|
| Pack (factual dossier) | `Reference` | Curated factual reference, not a takeaway or decision |
| Thesis (positioning judgment) | `Decision` | Claude's reasoned position on a ticker |

## 6. MCP tool surface

Five tools. Full schemas below. Implementation is a thin dispatch layer over corvia reads/writes, the shared collection function, and the local OTel trace store.

### 6.1 `list_watchlist`

```json
{
  "name": "list_watchlist",
  "description": "Returns the tickers currently being tracked, with the date each was last collected and the status of the last run.",
  "input_schema": {"type": "object", "properties": {}},
  "output_schema": {
    "type": "object",
    "properties": {
      "watchlist": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "ticker": {"type": "string"},
            "last_collected": {"type": "string", "format": "date-time"},
            "last_run_id": {"type": "string"},
            "last_run_status": {"enum": ["ok", "partial", "stale", "failed"]}
          }
        }
      }
    }
  }
}
```

Implementation: reads `watchlist.yaml`, queries corvia for the latest run per ticker, composes the response.

### 6.2 `get_ticker_context`

```json
{
  "name": "get_ticker_context",
  "description": "Returns the latest research pack for a ticker plus recent thesis history. Use this first when the user asks about a specific ticker.",
  "input_schema": {
    "type": "object",
    "properties": {
      "ticker": {"type": "string"},
      "thesis_history_limit": {"type": "integer", "default": 3}
    },
    "required": ["ticker"]
  }
}
```

Implementation: two corvia2 calls. One search filtered to `kind=reference`, tag `ticker:{ticker}`, latest only. One search filtered to `kind=decision`, tag `ticker:{ticker}`, limit N. Composed into one structured response.

### 6.3 `write_thesis`

```json
{
  "name": "write_thesis",
  "description": "Persists a new thesis for a ticker. Call this when your reasoning produces a new or materially updated thesis. The thesis is prose in your own voice, typically 200-500 words.",
  "input_schema": {
    "type": "object",
    "properties": {
      "ticker": {"type": "string"},
      "thesis": {"type": "string"},
      "supersedes": {"type": "string", "nullable": true, "description": "Entry ID of the prior thesis this replaces"},
      "change_summary": {"type": "string", "nullable": true}
    },
    "required": ["ticker", "thesis"]
  }
}
```

Implementation: single `corvia_write` call with `kind="decision"`, `agent_id="stock-agent-claude-query"`, `tags=["thesis", f"ticker:{ticker}"]`, `supersedes=[prior_id]` passed through natively to corvia2.

### 6.4 `rerun_ticker`

```json
{
  "name": "rerun_ticker",
  "description": "Triggers a fresh collection run for a ticker. Use when the user wants live data or when the latest pack is materially stale. Returns when collection completes (typically 1-3 minutes).",
  "input_schema": {
    "type": "object",
    "properties": {
      "ticker": {"type": "string"},
      "force": {"type": "boolean", "default": false}
    },
    "required": ["ticker"]
  }
}
```

Implementation: synchronously calls `collect_ticker(ticker, force=force)` from the shared internal module. Same function the cron entry point calls. Blocks until collection completes or errors. Returns metadata.

### 6.5 `get_run_trace`

```json
{
  "name": "get_run_trace",
  "description": "Returns the OTel trace for a collection run. Useful for debugging 'why did Phase 3 investigate X?' or 'how many tokens did this pack cost?'. Accepts a run_id or latest-per-ticker.",
  "input_schema": {
    "type": "object",
    "properties": {
      "run_id": {"type": "string", "nullable": true},
      "ticker": {"type": "string", "nullable": true},
      "latest": {"type": "boolean", "default": false}
    }
  }
}
```

Implementation: reads from the local OTel trace store (file-based JSONL, see [Section 7.3](#73-logging-and-tracing)). Returns spans with attributes (model, tokens, latency, cost) and events. The MCP tool is read-only.

### 6.6 Tools explicitly cut from v0.1

For the record, in case future versions want them:

- `get_run_status(date?)`: read from daily run log file if needed
- `search_all_theses(query)`: corvia generic search handles this if exposed later
- `live_price(ticker)`: already in latest pack
- `compare_tickers([tickers])`: Claude can call `get_ticker_context` twice
- `add_to_watchlist(ticker)` / `remove_from_watchlist(ticker)`: edit `watchlist.yaml`, cron picks it up

Any of these can be added in v0.2+ without changing the five-tool baseline.

## 7. Operations

### 7.1 Scheduling

Cron at 00:15 local time:

```crontab
15 0 * * * cd /path/to/stock-agent && uv run stock-agent collect --all >> logs/collect-$(date +\%Y\%m\%d).log 2>&1
```

On-demand collection happens via the `rerun_ticker` MCP tool, which invokes the same function synchronously inside the long-lived `serve` process.

### 7.2 Watchlist management

A YAML file at `~/.config/stock-agent/watchlist.yaml`:

```yaml
watchlist:
  - ticker: NVDA
    added: 2026-04-16
    notes: "AI datacenter primary exposure"
  - ticker: AMD
    added: 2026-04-16
  - ticker: MU
    added: 2026-04-16
  - ticker: MSFT
    added: 2026-04-16
  - ticker: SPY
    added: 2026-04-16
    notes: "benchmark ETF"
```

Edit the file, next cron run picks it up. `list_watchlist` reads it live. No management UI, no chat tool. This is a file, full stop.

### 7.3 Logging and tracing

Three layers of telemetry:

1. **OTel traces.** Every Gemini call, tool call, and collection phase is wrapped in an OpenTelemetry span using the [GenAI semantic conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/) (`gen_ai.system`, `gen_ai.request.model`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`, `gen_ai.response.finish_reason`). Custom attributes: `stock_agent.phase`, `stock_agent.ticker`, `stock_agent.run_id`, `stock_agent.est_cost_usd`. Exporter: local file-based OTLP writing to `traces/<date>.jsonl` by default. Optionally configurable to export to a Jaeger/Tempo endpoint.
2. **Collection run log**: `logs/collect-YYYYMMDD.log`. Structured JSONL, one line per significant event (phase start, tool call, error, phase complete). Contains timing, budget state, tool call summaries.
3. **Serve mode log**: `logs/serve.log`. One line per MCP tool invocation. Tool name, arguments, response size, duration, error if any.

Traces are the primary debugging surface. The `get_run_trace` MCP tool (Section 6.5) reads from the trace store and returns spans to Claude so it can inspect collection behavior directly.

Run logs and serve logs are human-greppable and rotated weekly.

### 7.4 Error recovery

Error categories and their handling are documented in [Section 4.8](#48-error-handling). The pattern across all of them: retry transient failures with exponential backoff, fall back to stale-but-valid state where possible, never let a single ticker's failure abort the whole run.

A `stock-agent status` CLI reads the run-status log and reports the last 7 days of nightly runs at a glance.

### 7.5 Agent identities in corvia

Two identities registered:

- `stock-agent-collector`: writes packs from `collect` mode
- `stock-agent-claude-query`: writes theses on Claude's behalf via the `write_thesis` MCP tool

Separation lets the audit trail distinguish machine-generated factual collection from Claude-authored reasoning. Useful for the v0.2 eval study and future "show me what Claude has said about X" queries.

### 7.6 Configuration

`~/.config/stock-agent/config.yaml`:

```yaml
gemini:
  api_key_env: GEMINI_API_KEY
  model: gemini-2.5-flash
  rpd_soft_cap: 400  # leave headroom under the 500 RPD ceiling

corvia:
  mcp_url: http://127.0.0.1:8020/mcp
  scope_id: corvia
  collector_identity: stock-agent-collector
  query_identity: stock-agent-claude-query

collection:
  max_calls_per_event: 5
  max_calls_per_ticker_phase3: 15
  max_tokens_per_ticker_hard: 150000
  max_tokens_per_ticker_soft: 80000
  chain_depth_limit: 1
  zero_return_streak_termination: 2
  cache_ttl_hours: 6
  news_lookback_hours: 72
  news_max_per_ticker_phase1: 30
  phase_5_enabled: true    # ablation toggle

otel:
  service_name: stock-agent
  exporter: file           # file | otlp | none
  file_path: ~/.local/share/stock-agent/traces
  otlp_endpoint: http://127.0.0.1:4318   # only when exporter: otlp

cost:
  # Public-rate reference prices for dollar rollup in pack metadata.
  # Free tier consumption is still $0 — these are the "what would this
  # cost at retail" numbers used for the eval study.
  gemini_flash_input_per_1m_tokens: 0.075
  gemini_flash_output_per_1m_tokens: 0.30

paths:
  watchlist: ~/.config/stock-agent/watchlist.yaml
  cache: ~/.cache/stock-agent
  logs: ~/.local/share/stock-agent/logs
  traces: ~/.local/share/stock-agent/traces
  staging: ~/.local/share/stock-agent/staging

prompts:
  reporter_version: v1
  triage_version: v1
  assembler_version: v1
  reviewer_version: v1
```

Hot-reloadable: no. Restart of `serve` mode required for config changes. v0.1 keeps this simple.

### 7.7 LLMClient protocol

All Gemini calls go through a `LLMClient` protocol (Python Protocol class):

```python
class LLMClient(Protocol):
    def generate(self, messages, system, model, response_schema) -> LLMResponse: ...
    def generate_with_tools(self, messages, system, model, tools) -> LLMResponse: ...
```

v0.1 ships one implementation: `GeminiClient`. The protocol exists so v0.2 can wire in Groq, local Ollama, or other providers for ablation studies and fallback without touching phase logic. Every phase calls `self.llm.generate(...)`, never the Gemini SDK directly.

## 8. Scope boundaries

### 8.1 In scope for v0.1

- `stock-agent` Python package with `collect` and `serve` entry points
- Phase 1 deterministic fetching: yfinance, SEC EDGAR via edgartools (XBRL + prose sections), news RSS. Insider transactions and 13F are optional best-effort.
- Phase 2-5 Gemini investigation loop with budgets and termination rules
- Pack and thesis schemas targeting corvia2, write integration via corvia2 MCP
- 5 MCP tools (`list_watchlist`, `get_ticker_context`, `write_thesis`, `rerun_ticker`, `get_run_trace`)
- YAML watchlist, cron scheduling
- Two agent identities in corvia2
- 5-ticker watchlist for dogfooding: NVDA, AMD, MU, MSFT, SPY
- End-to-end run from cron fire to Claude query against a real pack
- README with architecture diagram, seam rules, and honest "what does not work yet"
- 2-minute demo video showing one full flow
- GitHub repo is public with a permissive license
- Pydantic canonical schemas (`stock_agent/models.py`) with validation + 1-retry on LLM phase failures
- Prompt injection sandboxing on Phase 3 fetched content (`<untrusted_source>` delimiters, size caps, content-type checks)
- OTel tracing with GenAI semantic conventions, file exporter, `get_run_trace` MCP tool
- `LLMClient` provider-agnostic protocol (v0.1 wires Gemini only)
- Dollar cost rollup in pack metadata (`est_cost_usd` at public retail rates)
- Phase 5 ablation toggle + one comparison run (on vs off) on the micro-eval ticker
- **Micro-eval**: 1 ticker x 3 questions x 2 arms = 6 runs, results in README at ship time
- Prompt regression harness scaffolding (`fixtures/`, `scripts/prompt_regression.py`, 1 fixture captured Day 7)

### 8.2 Out of scope, with planned version placement

| Feature | Version | Reason for deferral |
|---|---|---|
| Full 5-ticker x 3-question x 2-arm eval study | v0.2 | v0.1 ships 1-ticker micro-eval; full run needs baseline stability |
| Full prompt regression harness (3-5 fixtures + LLM-judge grading) | v0.2 | v0.1 ships scaffolding only |
| Longitudinal consistency backtest (4 historical quarters) | v0.2 | Backdating infrastructure cost |
| Parallel ticker collection | v0.2 | Rate limit accounting complexity |
| Delta-aware collection (skip unchanged) | v0.2 | Need a week of baseline runs to model the change rate |
| Incremental Phase 3 (cache prior investigations) | v0.2 | Same reason |
| Failure post-mortem doc | v0.2 | Written after v0.1 ships with real operational data |
| Shariah screening (US stocks via Zoya / S&P DJ Islamic) | v0.3 | Niche feature, deferrable |
| PDF parsing of glossy annual reports | v0.3 | Significant work, low marginal value |
| Bull/Bear multi-agent debate (TradingAgents pattern) | v0.3 | Adds complexity, needs single-agent baseline first |
| Bahasa Malaysia output | v0.3 | Stretch feature |

### 8.3 Out of scope, never (explicit)

- LangChain, LangGraph, Pydantic-AI, CrewAI, AutoGen, any agent framework
- Live buy/sell recommendations
- Paper trading or brokerage integration
- Bursa Malaysia coverage (dropped during domain pivot)
- A web frontend (Claude Code/Desktop is the UI)
- Cloud deployment in v0.1 (local-first only)

## 9. Eval study

v0.1 ships a **micro-eval** (1 ticker). v0.2 runs the **full study** (5 tickers).

### 9.1 Claim being tested

> Pre-computing structured context via a cheap extractor (Gemini Flash) lets the expensive reasoner (Claude) answer each query at meaningfully lower token spend than fetching live each time, with no quality loss.

This isolates the contribution of the pre-built pack. Both arms use the same reasoner and the same finance-aware framing.

### 9.2 Arms

**Arm 1 -- stock-agent (treatment):** Claude Code session with `stock-agent` MCP connected. Claude calls `get_ticker_context`, loads the pre-built pack and thesis history, reasons from there, writes the answer.

**Arm 2 -- fair baseline (control):** Fresh Claude Code session, no `stock-agent` MCP. Claude uses WebSearch and WebFetch with a finance-aware system prompt instructing it to gather company news, recent filings, and price action before answering. Same model, same questions, same reasoning budget.

### 9.3 Subjects and scale

**v0.1 micro-eval:** 1 ticker (MU), 3 questions, 2 arms = **6 runs**.
**v0.2 full eval:** 5 tickers (NVDA, AMD, MU, MSFT, SPY), 3 questions, 2 arms = **30 runs**.

### 9.4 Questions (held constant across arms and versions)

1. "Write a current research note on {ticker}. Cover thesis, recent developments, key risks, and notable catalysts."
2. "What has materially changed for {ticker} since last quarter?"
3. "What are the top three risks for {ticker} right now, and why?"

### 9.5 Phase 5 ablation sub-study (v0.1)

In addition to the 2-arm comparison, v0.1 runs Arm 1 twice on MU:

- Once with `phase_5_enabled: true` (default)
- Once with `phase_5_enabled: false`

Same 3 questions. Isolates what the relevance review step actually contributes to pack quality. Produces the most interview-ready chart: "here is what reflection bought me."

### 9.6 Measured per run

- Claude input tokens
- Claude output tokens
- Wall-clock latency
- Tool call count (Arm 1: `get_ticker_context`; Arm 2: WebSearch/WebFetch)
- Gemini tokens consumed for Arm 1 (prorated from OTel traces)
- **Dollar cost at public retail rates** (both arms), broken down by model
- Final answer text, saved verbatim

### 9.7 Grading

1. **LLM-as-judge (primary).** Gemini 2.5 Pro free tier reads paired answers blind. Scores each on three axes (0-5):
   - Factual grounding: are stated facts correct and source-attributable?
   - Insight quality: does the answer surface non-obvious implications?
   - Internal consistency: does the reasoning hold together?
   Rubric committed to `eval/rubric.md` in the repo.
2. **Manual spot-check.** Human-grade at least 2 of the 3 micro-eval pairs as calibration against the LLM judge. If disagreement exceeds 20% on the full v0.2 study, manual grading becomes primary.

### 9.8 Outputs

- Per-run results table (all measured fields)
- Aggregated table (averages, cost per quality point)
- Cost-quality scatter plot
- Phase 5 ablation comparison chart (v0.1)
- Full 5x3 benchmark artifact (v0.2)
- Blog post with methodology, numbers, honest failure modes (v0.2)

### 9.9 Effort estimate

- **v0.1 micro-eval:** 0.5 day (Day 13). 6 runs + 2 ablation runs + grading.
- **v0.2 full eval + writeup:** 2-3 days.

## 10. Success criteria for v0.1

The ship bar. Sixteen checkboxes. v0.1 ships when all are true.

**Core pipeline:**
1. Cron runs `stock-agent collect --all` nightly, completes successfully, writes 5 packs to corvia2
2. Claude Code connected to stock-agent MCP can call `list_watchlist` and see all 5 tickers with recent `last_collected` dates
3. Claude Code can call `get_ticker_context("NVDA")` and receive a pack with at least one investigated event containing verbatim primary-source quotes
4. Claude can reason from that pack to produce a coherent research note
5. Claude can call `write_thesis("NVDA", ...)` and the thesis writes to corvia2 with explicit supersession
6. A second query on the same ticker the next day surfaces the prior thesis and Claude can reference it

**Hardening:**
7. Collection run fails gracefully on at least one simulated error (rate limit, malformed Gemini response) without crashing the whole run
8. Pydantic validation catches and retries at least one malformed Gemini output during the 5-ticker run (verified in logs)
9. Prompt injection sandboxing: a Phase 3 run where fetched content is wrapped in `<untrusted_source>` delimiters without disrupting the pipeline
10. OTel traces are visible via `get_run_trace` for at least one completed collection run

**Eval and observability:**
11. Micro-eval complete: 6 runs (1 ticker x 3 questions x 2 arms) with numbers in README
12. Phase 5 ablation complete: one on-vs-off pack comparison with notes in README
13. Prompt regression harness scaffolding present: `fixtures/` dir, `scripts/prompt_regression.py`, 1 captured fixture

**Ship artifacts:**
14. 2-minute demo video exists showing one end-to-end flow
15. README includes architecture diagram, seam rules, and an honest "what does not work yet" list
16. GitHub repo is public with a permissive license

No subjective "looks good." When all sixteen are true, v0.1 ships and goes into job applications.

## 11. Timeline (two weeks)

### Week 1: harness core

| Day | Work |
|---|---|
| 1-2 | Python package skeleton, `LLMClient` protocol + `GeminiClient`, yfinance + SEC fetchers (edgartools), cache layer, watchlist loading |
| 3 | Pydantic canonical schemas (`models.py`), Phase 1 + Phase 2 end-to-end on one ticker with schema validation |
| 4 | Phase 3 tool set + investigation loop + budget enforcement + prompt injection sandboxing |
| 5-6 | Phase 4 + Phase 5 + pack schema, corvia2 write integration via MCP, end-to-end single ticker working |
| 7 | OTel tracing wired on all Gemini calls. Capture first regression fixture. End-to-end pipeline verified. |

### Week 2: serve mode + eval

| Day | Work |
|---|---|
| 8-9 | MCP server skeleton, 5 tools (including `get_run_trace`), corvia2 read integration |
| 10 | Claude Code end-to-end test, fix issues |
| 11 | 5-ticker watchlist run, cron setup, logging |
| 12 | Error handling pass, README, demo video recording |
| 13 | Micro-eval (6 runs, 2 arms) + Phase 5 ablation (2 packs) + numbers in README |
| 14 | Ship |

If Week 1 overruns, Day 13 absorbs it. Micro-eval shrinks to 1 ticker x 1 question x 2 arms (2 runs minimum).

## 12. Open questions and risks

### 12.1 Open questions -- resolved 2026-04-16

1. **Package name.** `stock-agent` placeholder retained for v0.1. Rename later if a better name surfaces.
2. **corvia write semantics for theses.** Resolved. Targeting corvia2, which natively supports explicit `supersedes: Vec<String>` via `corvia_write`. Packs map to `kind=Reference`; theses to `kind=Decision`. Structured metadata in YAML front-matter inside content; ticker + kind in tags. See Section 5.
3. **News RSS source list.** Validate during Day 3 implementation. Adjust based on which feeds are usable without auth.
4. **edgartools vs sec-edgar-downloader.** `edgartools` chosen. XBRL parsing + section access is a harder requirement than sec-edgar-downloader meets. Revisit only if a blocking issue surfaces.
5. **MCP Python SDK.** Official `mcp` package (FastMCP module). Stdio transport by default.

### 12.2 Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Gemini free tier quota changes mid-build | Medium | High | Soft cap config at 400 RPD instead of 500; provider-agnostic shape so swapping to Groq is straightforward |
| News RSS sources require auth or rate limit harshly | Medium | Medium | Diversify across 4-5 sources; fall back to URL list curated from manual searches |
| SEC EDGAR rate limits | Low | Medium | Polite headers, throttle to 1 req/sec, cache aggressively |
| Phase 3 investigation drifts beyond budget | Medium | Low | Hard caps in code, tested with deliberately ambiguous events on Day 5 |
| corvia2 `corvia_write` does not handle pack markdown cleanly | Low | Medium | Test on Day 6 with a real pack; YAML front-matter + markdown is a well-tested pattern |
| Claude Code MCP integration has stdio-vs-HTTP gotchas | Low | Medium | Test both transports on Day 10; default to stdio for simplicity |
| Two-week timeline slips | Medium | Medium | Day 13 buffer is real. If Week 1 takes 8 days instead of 7, cut error handling to "best effort" instead of robust |

### 12.3 What would invalidate this design

Three things would force a rework:

1. **Gemini free tier becomes inadequate.** If RPD drops below ~150 or TPM below ~50k, the design as-is does not fit. Mitigation: provider-agnostic interface allows swap to Groq Llama 3.3 70B free tier or local Ollama.
2. **corvia2 write performance is much worse than expected.** If a single pack write takes >5 seconds, nightly runs balloon. Mitigation: corvia2 writes are local (no network hop) and should be fast. If not, batch writes or switch to direct file writes as a deferred optimization.
3. **The "Gemini extracts, Claude reasons" split produces worse output than expected.** The v0.1 micro-eval (Section 9) tests this directly. If the 6 runs show Arm 1 quality is noticeably worse than Arm 2, the cost-quality claim is invalidated. Mitigation: the harness still works as a portfolio demo even if the thesis is wrong. An honest "here is what I expected and here is what I found" is more compelling than no data.

## 13. References

- corvia: this workspace's memory server, used as the storage and retrieval layer
- FinMem (arXiv 2311.13743): layered memory with decay, structurally informs the corvia mapping
- TradingAgents (arXiv 2412.20138): role decomposition and agentic loop patterns, prompts copied (not imported)
- FinRobot equity-research paper (arXiv 2411.08804): note schema influence
- FinAgent (arXiv 2402.18485): dual-level reflection pattern, informs the Phase 5 review
- FinanceBench (arXiv 2311.11944): hallucination failure taxonomy reference for Phase 4 grounding rules
- [SOTA survey doc](2026-04-15-sota-financial-research-agents.md): full literature triage
- [Domain selection doc](2026-04-15-domain-selection-job-vs-stocks.md): why stocks instead of job hunting
- [Reeval doc](2026-04-15-malaysia-agent-builder-reeval.md): why a custom harness instead of framework integration
