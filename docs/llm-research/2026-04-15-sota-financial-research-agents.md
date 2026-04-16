# SOTA Survey: LLM Agents for Financial Research (Build-Informed)

Date: 2026-04-15
Context: Before building the Bursa Malaysia longitudinal research agent, survey the state of the art and decide what to read, what to borrow, and what to skip. Build-informed bias: skim widely, deep-dive only on the 2-3 items closest to what actually ships. Research was delegated to a subagent and synthesized here.

Companion docs:
- [2026-04-14-portfolio-strategy-ai-engineer.md](2026-04-14-portfolio-strategy-ai-engineer.md)
- [2026-04-15-malaysia-agent-builder-reeval.md](2026-04-15-malaysia-agent-builder-reeval.md)
- [2026-04-15-domain-selection-job-vs-stocks.md](2026-04-15-domain-selection-job-vs-stocks.md)

## 1. Headline

The field has converged on multi-agent trading simulations that optimize PnL. Almost nobody evaluates research-note quality, almost nobody does longitudinal memory well, and nobody at all is working on Bursa Malaysia or Shariah compliance in the LLM literature. The build's differentiators are not inventions — they are genuine unoccupied niches. Three papers and two repos contain everything worth studying. Everything else is either orthogonal (RL trading, pretraining) or downstream commercial product shape.

## 2. What Actually Matters (The Five Reads)

Ranked. Read in order. Everything else in the doc is context for these five.

1. **FinMem** ([arXiv 2311.13743](https://arxiv.org/abs/2311.13743), [repo](https://github.com/pipiku915/FinMem-LLM-StockTrading)) — the only published architecture that treats agent memory as layered and time-decaying. Working memory plus tiered long-term memory with explicit aging. This is structurally what corvia should expose to the harness for this agent. Read the memory module file and the profiling module; skip the trading loop.
2. **TradingAgents** ([arXiv 2412.20138](https://arxiv.org/abs/2412.20138), [repo](https://github.com/TauricResearch/TradingAgents), 50.6k stars) — LangGraph-based multi-agent system with role decomposition (Fundamentals, Sentiment, News, Technical, Bull/Bear debate, Trader, Risk Manager). Read `agents/` and `graph/` directories. **Copy the role prompts verbatim, do not import the package.** The 50k stars are telling you the *product shape* (AI analyst team) has pull even when the PnL claims are thin. Gemini-compatible out of the box, which matches our stack.
3. **FinRobot equity-research paper** ([arXiv 2411.08804](https://arxiv.org/html/2411.08804v1), [repo](https://github.com/AI4Finance-Foundation/FinRobot)) — the closest published work to our actual output target. Produces sell-side-format research reports via a Data-CoT / Concept-CoT / Thesis-CoT chain. Human expert eval: 9.4/9.3/8.2 on accuracy/logic/story. Use their report structure (thesis, projections, valuation, competitors, risks) as the v0.1 output schema verbatim. Ignore the LLMOps/finetuning scaffolding.
4. **FinAgent** ([arXiv 2402.18485](https://arxiv.org/abs/2402.18485), KDD'24) — dual-level reflection module: fast reflection after each run, slow reflection that rewrites the standing thesis. This is the mechanic for "admit prior mistakes" cleanly. The reflection loop transfers; the trading wrapper does not.
5. **FinanceBench** ([arXiv 2311.11944](https://arxiv.org/abs/2311.11944)) — not for evaluation, for its failure taxonomy. 10,231 open-book QA over 10-Ks documenting exactly how frontier LLMs hallucinate on filings. Use it to design grounding checks, not as a benchmark.

Everything else: survey paper at most, then move on.

## 3. Area-by-Area Findings (Compressed)

### 3.1 Academic foundations (mostly skip)

BloombergGPT, FinGPT, FinMA/PIXIU, FinLLaMA, FinBERT. All are pretraining or finetuning efforts. None are useful for a Python agent builder who will not train. FinBERT is a viable cheap sentiment baseline if needed. FinGPT's data connectors are worth skimming if we end up scraping news. Frontier models with good prompts beat all of them on note generation.

**Decision:** no time spent on this area beyond knowing the names exist for interview small-talk.

### 3.2 Agent architectures (the main event)

Covered above in the five reads. Quick triage on the rest:
- **FINCON** (NeurIPS'24) — verbal reinforcement between agents updating a belief memory. Spiritually aligned, less code traction. 15-minute skim at most.
- **AlphaAgents** ([arXiv 2508.11152](https://arxiv.org/abs/2508.11152), Aug 2025) — role-based multi-agent for portfolio construction. Recent, worth a prompt-structure skim.
- **AlphaAgent / Alpha-GPT / StockAgent** — alpha-factor mining and trading-behavior simulation. Orthogonal. Skip.
- **Survey paper** ([arXiv 2408.06361](https://arxiv.org/html/2408.06361v2)) — read this first, 30 minutes, gets the taxonomy without reading each primary source.

### 3.3 Benchmarks (mostly not useful)

FinanceBench (grounding gate only, not eval), FinQA / ConvFinQA (table QA, wrong axis), FiQA (old), BizBench (skip), FinBen (optional subset if we need a published number for the blog), FinanceQA ([arXiv 2501.18062](https://arxiv.org/abs/2501.18062)) is the closest to analyst-task QA and worth skimming, MultiFinBen (multilingual — worth checking if SEA languages are in it).

**The hard truth:** there is no published benchmark for note quality or longitudinal consistency over quarters. The closest is LT-QA (longitudinal tracking QA across filings from the same company). **This absence is the strongest single finding in the survey.** Building a small internal eval — 5 companies, 4 quarters, pairwise LLM-judge on note updates — is itself a portfolio artifact because no one else has done it. See section 4.

### 3.4 Commercial products (learn the shape)

Bloomberg Terminal AI, AlphaSense, Hebbia, Rogo, Finchat, Perplexity Finance, OpenBB Terminal AI.

Takeaways that transfer to a solo build:
- **Moat is data, not model.** BloombergGPT's moat is the Terminal corpus, not the 50B params. This validates the "Bursa specialization" framing.
- **Hebbia's matrix UI** (rows = documents, columns = questions) is the product shape for "compare all Bursa banks' latest quarterlies." File away for v0.3+.
- **Rogo's pitch** is literally "AI analyst teammate." Same pitch as the portfolio story. Use it shamelessly in the blog post framing.
- **Perplexity Finance loses to specialized context.** Argues directly for the Bursa angle: unmoated retrieval over US-centric data is the losing position, local specialization wins.

**One-sentence pitch:** "Hebbia/Rogo but for Bursa, with memory." Malaysian fintech interviewers will grok this instantly.

### 3.5 Open-source to borrow from

| Repo | Action |
|---|---|
| TradingAgents | Read `agents/` and `graph/`. Copy prompts, do not import. |
| FinMem-LLM-StockTrading | Read the memory module file. Structurally echo in corvia mapping. |
| FinRobot | Read equity-research prompts and section templates. |
| OpenBB Platform | **Check Bursa Malaysia coverage first** — if yes, this is the data layer and saves a week of scraping. Already has an MCP server. |
| FinGPT | Data-pipeline scraping code only. Model is stale. |
| FinRL | Skip. RL for trading, wrong axis. |
| LangChain/LlamaIndex finance templates | Skip. Abstraction bloat; we're on raw SDK on purpose. |

### 3.6 The niches (this is where the moat lives)

**Shariah + LLM literature: empty.** Commercial screeners (Zoya, Islamicly) are rule-based, applying AAOIFI business-activity screens and financial ratios. No published NLP work. The Malaysian Securities Commission maintains the Shariah Advisory Council (SAC) list as authoritative ground truth. **The play:** encode AAOIFI ratios as a deterministic tool the agent calls, cite the SAC list for status, let the LLM annotate. This puts us ahead of the academic literature by default because the literature does not exist.

**Bursa / KLSE LLM work: essentially nil.** One IEEE paper on LSTM price prediction for FBMKLCI (not LLM, not useful). A `equitorium` PyPI package claims some analyst-report summarization — 10-minute audit worth doing. Otherwise empty. This is the gap.

**Malay-language financial NLP: thin but exists.** [malaysia-ai](https://huggingface.co/malaysia-ai) on HuggingFace has Malay corpora and a sentiment model. No finance-specific Malay corpus. Good news: most Bursa filings are in English anyway. BM is a v0.3 stretch feature at best.

**Local analyst workflow:** CIMB, Maybank IB, RHB, Kenanga, Public Investment Bank publish research notes publicly as PDFs. **Scraping ten of these as few-shot examples for the note-style prompt is the single highest-leverage thing we can do for output quality.** There is no formal workflow documentation — the PDFs *are* the workflow.

## 4. What This Changes in the Build Plan

The survey produces six concrete build decisions that update the prior domain doc.

### 4.1 Output schema: adopt FinRobot's structure verbatim

Instead of inventing a research-note template, use FinRobot's expert-reviewed schema:
1. Thesis (one paragraph)
2. Projections (numbers with sources)
3. Valuation (ratios, peer context)
4. Competitors (peer set)
5. Risks (bull/bear breakdown)

Add two v0.1-specific sections:
6. Shariah status (from SAC list) and compliance notes
7. Open questions (what the agent does not know yet)

### 4.2 Memory shape: mirror FinMem's tiered design in corvia

Three tiers of memory for the agent, mapped to corvia entries:
- **Working memory** — this run's scratchpad, not persisted
- **Short-term** — last 1-2 runs of the same ticker, always loaded
- **Long-term** — full history of the ticker, retrieved by relevance with explicit decay

Corvia's temporal edges and entry supersession are a near-direct fit. The agent does not have to reinvent this — it just exposes the tiering in prompts.

### 4.3 Reflection mechanic: adopt FinAgent's dual-level pattern

Two reflection loops, clearly separated:
- **Fast reflection** (every run): "Did I correctly use the tools I called? Did my note contradict the data I fetched?"
- **Slow reflection** (when new data arrives for a ticker with a prior note): "Does the new data change the thesis? Which specific claims in the prior note are now wrong?"

The slow reflection produces the most valuable demo artifact: a public diff where the agent names what it got wrong.

### 4.4 Agent topology: single agent with tools first, debate later

The survey's clearest trap is multi-agent-for-multi-agent's-sake. Papers use 5-7 agents because the diagram looks impressive, not because it works better for our scale. v0.1 is a **single agent with a clean tool set**. The Bull/Bear debate from TradingAgents is a v0.2 addition *only if* the single-agent version is shipping and measured first.

### 4.5 Data layer: check OpenBB before building scrapers

This was already on the week-1 spike list but the survey elevates it. OpenBB is ~40k stars, has an MCP server, and if Bursa Malaysia coverage exists through any of its providers, we save a week of scraping and gain a legitimate data-layer story. If not, fall back to yfinance / i3investor / KLSE Screener as planned.

### 4.6 Eval: build the benchmark the field is missing

This is the single biggest finding. **No published benchmark measures longitudinal note consistency.** Build a small internal one and make it the backbone of the blog post:
- **5 Bursa tickers** (Maybank, Tenaga, Petronas Chemicals, Public Bank, one non-Shariah-compliant control like Genting)
- **4 quarters of backdated runs** — generate a note for each ticker at Q1, then re-run with memory at Q2, Q3, Q4
- **Three metrics:**
  1. Factual grounding against FinanceBench-style evidence checks
  2. Inter-quarter consistency (LLM-judge pairwise: does the Q3 update cohere with Q2?)
  3. Self-correction rate (when Q3 data contradicts the Q2 thesis, does the agent flag it?)
- **Public release:** the 5-ticker benchmark itself becomes a GitHub artifact tied to the blog post

The framing: "I built the eval the field is missing, and here are the numbers on my agent." That is a stronger portfolio claim than any existing paper's PnL number.

## 5. Surprises, Traps, and Gaps

1. **Almost every finance-agent paper evaluates on PnL.** Even the ones that generate text optimize for trade returns. Note quality, factual grounding, and calibrated uncertainty are wide open. Lean into this explicitly in the blog.
2. **Longitudinal memory is named but not measured.** FinMem and FinAgent gesture at it; neither tests whether the agent's thesis actually improves across quarters. LT-QA is the closest. The 5-ticker benchmark in 4.6 fills this hole.
3. **Shariah + LLM is empty.** Free moat. The combination of frontier LLM + deterministic AAOIFI rule tool + SAC list ingestion is essentially unshipped in the literature.
4. **Bursa data plumbing is the biggest schedule risk.** Bursa has no EDGAR equivalent. If OpenBB does not cover it, budget explicit time and cache aggressively.
5. **Trap: LangChain/LangGraph creep.** TradingAgents is built on LangGraph. The temptation to "just import it" is the exact mistake that breaks the harness-from-scratch portfolio angle. Rule: copy prompts, copy schemas, copy structural ideas. Do not import.
6. **Trap: multi-agent-for-multi-agent's-sake.** 5-7 agent topologies are overkill and harder to debug than a single agent with good memory. Single agent first.
7. **One upside surprise:** TradingAgents hit 50.6k stars in ~15 months. That is Cursor-level pull for a research repo. It confirms the "AI analyst team" product shape has genuine market appetite even when the PnL claims are thin — which validates the framing, not the finance.

## 6. Updated Action Items

Replaces the action items in [2026-04-15-domain-selection-job-vs-stocks.md](2026-04-15-domain-selection-job-vs-stocks.md).

**Week 0 (this week — reading before building):**
1. Read the survey paper ([arXiv 2408.06361](https://arxiv.org/html/2408.06361v2)) — 30 min, one-pass taxonomy
2. Read the FinMem paper and memory module source — 1-2 hours
3. Clone TradingAgents, read `agents/` and `graph/` directories — 2-3 hours
4. Read FinRobot equity-research paper for the note schema — 30 min
5. Read FinAgent's reflection module section — 30 min
6. 10-minute audit of `equitorium` PyPI package to confirm it is not worth using
7. **Data plumbing spike:** check if OpenBB Platform has Bursa Malaysia coverage. If yes, save a week. If no, test yfinance `.KL` coverage on 3 tickers.

**Week 1:** harness v0.1 as planned in prior doc. First tool is `http_get`. Gemini Flash provider.

**Week 2:** add `bursa_snapshot`, `bursa_announcements`, `shariah_status` (SAC list lookup), `research_note_write` (corvia backend). Adopt FinRobot note schema. Single-agent topology.

**Week 3:** 5-ticker longitudinal benchmark run. Three metrics from 4.6. Blog post draft.

**Explicit non-goals reaffirmed:**
- No Bull/Bear debate in v0.1 (v0.2)
- No PDF annual-report parsing in v0.1 (v0.2)
- No Bahasa Malaysia output (v0.3)
- No multi-agent topology (v0.2 at earliest, only after single agent is measured)
- No LangChain / LangGraph imports, ever

## 7. Key Strategic Insights

1. **The three differentiators (Bursa coverage, Shariah, longitudinal memory) are all genuine gaps in the literature.** This is not positioning — it is an accurate read of what the field has and has not done.
2. **The eval itself is the moat.** Every paper optimizes for PnL; none measure note quality or inter-quarter consistency. Shipping a 5-ticker longitudinal benchmark is a stronger portfolio artifact than the agent itself.
3. **Adopt prior-art structure, not prior-art code.** FinRobot's report schema, FinMem's memory tiers, FinAgent's dual reflection, TradingAgents' role prompts — all are borrowable as *shapes*. None should be imported as dependencies. The harness-from-scratch principle is non-negotiable.
4. **A single well-instrumented agent beats a poorly-debugged multi-agent.** The diagram-impressive topologies in the literature are for papers, not for shipping.
5. **One week of reading before coding is a bargain.** The cost is 5-8 hours; the benefit is avoiding three classes of mistake the field has already made.

## 8. What to Do Right Now

Three choices, not overlapping:
1. **Start the Week 0 reading list** — begin with the survey paper and FinMem.
2. **Data plumbing spike on OpenBB + Bursa** — the single biggest schedule risk; worth clearing first.
3. **Start building the harness repo** — v0.1 loop with `http_get`, independent of the reading.

Reading first is the safer call given the research just surfaced six concrete build decisions that would change code already written. Suggest: Week 0 reading Monday-Tuesday, OpenBB spike Wednesday, harness v0.1 starts Thursday.

## Sources

Full source list from the subagent research pass:
- TradingAgents: [paper](https://arxiv.org/abs/2412.20138), [repo](https://github.com/TauricResearch/TradingAgents)
- FinMem: [paper](https://arxiv.org/abs/2311.13743), [repo](https://github.com/pipiku915/FinMem-LLM-StockTrading)
- FinAgent: [paper](https://arxiv.org/abs/2402.18485)
- FinRobot: [equity-research paper](https://arxiv.org/html/2411.08804v1), [repo](https://github.com/AI4Finance-Foundation/FinRobot)
- FinGPT: [repo](https://github.com/AI4Finance-Foundation/FinGPT)
- AlphaAgents: [arXiv 2508.11152](https://arxiv.org/abs/2508.11152)
- AlphaAgent: [arXiv 2502.16789](https://arxiv.org/abs/2502.16789)
- LLM-agents-in-financial-trading survey: [arXiv 2408.06361](https://arxiv.org/html/2408.06361v2)
- FinanceBench: [arXiv 2311.11944](https://arxiv.org/abs/2311.11944)
- FinanceQA: [arXiv 2501.18062](https://arxiv.org/abs/2501.18062)
- FinBen: [arXiv 2402.12659](https://arxiv.org/html/2402.12659v2)
- OpenBB Platform: [repo](https://github.com/OpenBB-finance/OpenBB)
- Zoya: [zoya.finance](https://zoya.finance/)
- Islamicly: [islamicly.com](https://www.islamicly.com/)
- malaysia-ai corpora: [HuggingFace](https://huggingface.co/malaysia-ai)
- AlphaSense: [alpha-sense.com](https://www.alpha-sense.com/)
- Hebbia: [hebbia.com](https://www.hebbia.com/)
