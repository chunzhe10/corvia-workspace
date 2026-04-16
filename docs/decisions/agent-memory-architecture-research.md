# Agent Memory Architecture Research

> **Date**: 2026-04-16
> **Status**: Active study — ongoing exploration
> **Scope**: How AI agents persist knowledge from conversations, enforcement mechanisms,
> and how corvia can evolve to support passive knowledge capture.

## Problem Statement

Three tensions in agent knowledge persistence:

1. **Prompt instructions are unreliable** — best models follow <30% of instructions in
   agentic scenarios (AGENTIF benchmark). Degrades further over long sessions with compaction.
2. **Hooks are brittle** — binary enforce/block, coupled to a specific binary, can brick
   sessions when versions mismatch (experienced in corvia v1→v2 migration).
3. **The write-up tax** — the agent already produces rich explanations in terminal output.
   Paying tokens again to explicitly write to a knowledge store is waste.

---

## Part 1: Industry Landscape (2026)

### Memory Capture Spectrum

```
Passive ◄──────────────────────────────────────────► Active
(observe conversation,           (agent explicitly calls
 extract post-hoc)                a write tool mid-task)

MemMachine          Claude Auto Dream    Mem0         Letta/MemGPT
(raw storage +      (grep logs +         (LLM extract  (agent self-edits
 smart retrieval)    batch consolidate)   every turn)   memory via tools)
```

### System Comparison

| System | Capture | Extraction | Retrieval | Token Cost | Storage |
|--------|---------|------------|-----------|------------|---------|
| **Mem0** | Implicit (auto) | LLM extraction + update (2 calls/turn) | Vector + graph hybrid | ~7K tokens/conv (90% savings) | Vector DB + knowledge graph |
| **Letta/MemGPT** | Implicit (agent self-manages) | LLM reasoning → tool calls | Vector search + date filtering | Fits in context; recursive summarization | Core (in-context) + vector DB + conversation DB |
| **LangMem** | Both (foreground or background) | LLM parallel tool calling | Vector semantic search + metadata | LLM call per batch | LangGraph BaseStore (pluggable) |
| **Zep/Graphiti** | Implicit (auto) | LLM entity/relation extraction + reflection | Hybrid: cosine + BM25 + BFS + reranking | ~1.6K tokens/query (vs 115K full) | Temporal knowledge graph |
| **Claude Code** | Hybrid (CLAUDE.md manual + auto memory) | LLM decides during session | File read on demand; 200-line index | 200 lines / 25KB auto-loaded | Plain text files on disk |
| **ChatGPT** | Primarily explicit | Bio tool (LLM tool call) + background distillation | Direct injection (no search) | All facts injected every time | Server-side, ~33 facts |
| **MemMachine** | Passive (raw storage) | None at ingestion | Sentence-level indexing + smart retrieval | ~80% fewer tokens than Mem0 | Raw conversation episodes |

### Key Research Findings

1. **Agent capability > storage sophistication**: Letta benchmarks show simple filesystem memory
   (74.0%) outperformed Mem0's graph variant (68.5%) on LoCoMo.

2. **Recall > storage**: MemMachine's core insight: "how data is recalled matters more than
   how it is stored, provided storage preserves ground truth."

3. **No system solves staleness**: Frequently-accessed memories become confidently wrong when
   underlying facts change. Auto Dream's date-conversion is the most explicit attempt.

4. **The LLM is always the memory manager**: Every production system uses the LLM itself to
   decide what to remember. No rule-based extraction works at scale.

5. **File-based memory is surprisingly competitive**: Claude Code's plain-text CLAUDE.md +
   MEMORY.md approach works well when the agent is competent at self-management.

---

## Part 2: Enforcement Spectrum

From weakest to strongest, with reliability data:

| Level | Mechanism | Reliability | Best For | Failure Mode |
|---|---|---|---|---|
| 1 | System prompt instructions | ~30-77% | Soft preferences, style | Ignored after context dilution |
| 2 | CLAUDE.md / AGENTS.md directive language | ~60-80% | Core workflow rules | Competes with default behavior |
| 3 | Skills with optimized descriptions | ~77-100% activation | Multi-step procedures | Steps skipped silently |
| 4 | MCP tools (instructed to call) | ~70-90% | Knowledge retrieval | Agent skips the call |
| 5 | UserPromptSubmit hook → inject reminder | ~95%+ visibility | Periodic nudges | Adds noise |
| 6 | PreToolUse hook → allow + additionalContext | ~99% visibility | Just-in-time guidance | Agent sees but may not act |
| 7 | PreToolUse hook → deny | 100% enforcement | Safety gates only | Breaks workflow if buggy |
| 8 | SessionStart compact matcher | 100% injection | Surviving context loss | Only fires on compaction |

### Non-blocking hook pattern (new in Claude Code)

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "REMINDER: Check corvia knowledge base before code search."
  }
}
```

This allows the tool call to proceed while injecting a reminder. Eliminates the binary
block/allow problem of v1 hooks.

### Recommended enforcement per use case

| Use case | Old (v1 hooks) | Recommended | Why |
|---|---|---|---|
| Check KB before code search | PreToolUse deny on Grep/Glob | Level 6: allow + additionalContext | Non-destructive; reminder visible to agent |
| Document placement rules | PreToolUse deny on Write/Edit | Level 7: deny (keep) via HTTP hook | Genuine policy gate; wrong location = bug |
| Save discoveries | PostToolUse on Bash | Level 5: UserPromptSubmit periodic reminder + passive capture | Eliminate write-up tax entirely |
| Session cleanup | SessionEnd command | SessionEnd async hook | Side-effect, not enforcement |

---

## Part 3: Architectural Patterns

### 1. MemMachine — Ground Truth Preservation

Store raw conversation episodes with sentence-level indexing. Skip the extraction LLM
entirely. Let retrieval handle the intelligence.

- **Token cost**: Zero during session. Embedding cost at end.
- **Key insight**: The raw conversation IS the knowledge. You need indexing, not re-generation.
- **Benchmark**: Only +0.8% accuracy improvement from sentence-level over message-level indexing
- **Paper**: arxiv 2604.04853

### 2. Claude Auto Dream — Grep-Based Signal Detection

Don't LLM-scan entire transcripts. Grep for specific patterns (user corrections, explicit
saves, recurring themes, decisions). Cheap, fast, targeted.

- One session consolidated 913 transcripts in 8-9 minutes.
- Pattern: Orient → Gather Signal (grep) → Consolidate (LLM) → Prune & Index
- Dual gate trigger: 24h elapsed AND 5+ sessions accumulated

### 3. Nurture-First — Tagged Output

Tag content at generation time (`[DECISION]`, `[INSIGHT]`, `[ERROR]`) so extraction is a
parser, not an LLM. Nobody has fully built this yet — open architectural opportunity.

- **Paper**: arxiv 2603.10808 ("Conversational Knowledge Crystallization")
- Four-phase: daily tagged output → accumulation → periodic LLM consolidation → structured assets

### 4. Karpathy LLM Wiki — Compiler Pattern

Raw documents treated as source code, compiled through LLM passes into structured artifacts.
Three-directory pattern: `raw/` → `wiki/` → output.

### 5. Screenpipe — Event-Driven Passive Capture

Instead of recording everything, capture only on state changes (app switch, click, typing
pause). Pairs screenshot with OS accessibility tree. Runs as MCP server.

- ~5-10 GB/month, 5-10% CPU
- "Pipes" are scheduled AI agents that process captured data

### 6. xMemory — Hierarchical Progressive Summarization

Four-level hierarchy: raw messages → episodes → semantics → themes.
Top-down retrieval: themes → semantics → episodes → raw.
50%+ token cost reduction vs traditional RAG.

- **Paper**: arxiv 2602.02007

### 7. Zep/Graphiti — Temporal Knowledge Graph

Bi-temporal model tracking both system time and real-world validity time.
Conflict resolution: new edges invalidate old ones (never delete).
Three-stage retrieval: search (cosine + BM25 + BFS) → rerank → construct.

### 8. FadeMem — Dual-Layer Differential Decay

Most mathematically rigorous decay model:
- Long-term layer: `beta = 0.8` (sub-linear decay, half-life ~11.25 days)
- Short-term layer: `beta = 1.2` (super-linear decay, half-life ~5.02 days)
- Promotion to long-term: importance >= 0.7. Demotion: importance < 0.3.
- Hysteresis gap prevents oscillation between tiers.
- Memory fusion when `similarity > 0.75` and `time_gap < T_window`
- Reduces storage by 45% while maintaining superior critical information retention.

- **Paper**: arxiv 2601.18642

---

## Part 4: Session Log Formats (Harness-Agnostic)

### Format landscape

| Harness | Format | Location | Structured? | Watcher-friendly? |
|---------|--------|----------|-------------|-------------------|
| Claude Code | JSONL | `~/.claude/projects/` | Yes (rich) | Yes (append-only) |
| Codex CLI | JSONL | `~/.codex/sessions/` | Yes | Yes (append-only) |
| Copilot CLI | JSONL + YAML + SQLite | `~/.copilot/session-state/` | Yes | Partial |
| Cursor | SQLite (vscdb) | Application Support | Key-value | No (polling) |
| Gemini CLI | JSON | `~/.gemini/tmp/` | Yes | Yes (file per session) |
| Aider | Markdown | Working directory | Weakly | Yes (append-only) |

### Claude Code JSONL schema (most detailed)

Message types: `user`, `assistant`, `system`, `summary`, `result`, `file-history-snapshot`,
`last-prompt`. Each message has `uuid`, `parentUuid` (DAG structure), `timestamp`,
`sessionId`, `cwd`, `gitBranch`, `version`.

Assistant messages include: `model`, `content` (array of `text`/`tool_use`/`thinking` blocks),
`stop_reason`, `usage` (with full token breakdown including cache hits).

**SessionEnd hook** receives: `session_id`, `transcript_path` (absolute path to JSONL),
`cwd`, `reason`. This is the natural integration point — the hook fires when a session ends.

### Existing tools that parse session logs

- **session-graph**: Parses Claude Code JSONL, DeepSeek, Grok, Warp into RDF knowledge graph
  with LLM-powered triple extraction (24 curated predicates)
- **crune**: Mines recurring workflow patterns from Claude Code sessions, builds semantic
  knowledge graph, synthesizes reusable skills
- **Severance**: Hooks-based memory for Claude Code using SessionStart/End lifecycle
- **claude-conversation-extractor**: Extracts conversations to readable formats
- **cursor-db-mcp**: MCP server for querying Cursor's SQLite conversation store

---

## Part 5: Hot Memory with Decay

### Decay models compared

| System | Decay function | Trigger | Key feature |
|---|---|---|---|
| FadeMem | `v(t) = v(0) * exp(-λ*(t-τ)^β)` | Per-access | Dual-layer (short/long-term) |
| YourMemory | `strength = I * e^(-λ*days) * (1 + recalls*0.2)` | 24h scheduler | Ebbinghaus curve |
| Hippo | `strength = init * 2^(-elapsed/half_life) * reward` | Manual `sleep` command | Error memories get 2x half-life |
| Corvia v1 (designed) | `score = 0.35*D + 0.30*A + 0.20*G + 0.15*C` | Background task (60min) | Four-factor weighted |

### Classify at write time, decay by classification

The single most important insight across all systems. Different content types need different
decay rates:

| Content type | Decay rate | Half-life | Examples |
|---|---|---|---|
| Structural | 0.00 (permanent) | ∞ | Code patterns, API docs |
| Decisional | 0.15 (slow) | ~46 days | Architecture decisions, design rationale |
| Procedural | 0.10 (very slow) | ~69 days | How-to workflows, build commands |
| Analytical | 0.30 (moderate) | ~23 days | Findings, benchmarks, perf observations |
| Episodic | 0.60 (fast) | ~11 days | Debugging context, session notes |

Maps directly to corvia's existing `Kind` enum. Add a new kind (e.g., `Ephemeral`) for
auto-captured session material that should decay fastest.

### Corvia v1's designed-but-dropped GC system

Issues #14-#27 documented a complete tiered lifecycle that was cut during the v2 rewrite:

- **Retention score**: `score = 0.35*D(t,α) + 0.30*A(access_count, days_since) + 0.20*G(inbound_edges) + 0.15*C(confidence)`
- **Tier thresholds with hysteresis**: Hot→Warm at <0.50, Warm→Cold at <0.25, Cold→Forgotten at <0.05.
  Promotion: Cold→Warm at ≥0.35, Warm→Hot at ≥0.60. Hysteresis prevents oscillation.
- **GC worker**: Background tokio task, 60min default. One tier step per cycle. Batched Redb writes (100/txn).
- **Safeguards**: Supersession chain protection, auto-protect structural/high-confidence entries,
  pinning, budget-based capacity limits.

This is prior art that can be revived for v2.

### Access-based refresh (the "testing effect")

Every retrieval strengthens a memory:
- Hippo: extends half-life ~2 days per retrieval
- YourMemory: `1 + 0.1 * recall_count` multiplicative boost
- FadeMem: recency factor in importance calculation
- Practical: on every `corvia_search` result returned, increment `access_count` and
  update `last_accessed` on the matching entries.

### Consolidation triggers

| System | Trigger |
|---|---|
| Claude Auto Dream | 24h + 5 sessions (dual gate) |
| LangMem | Debounced delay (30-60min production) |
| Hippo | Manual `hippo sleep` command |
| FadeMem | Continuous (computed per-access) |
| Corvia v1 design | Background tokio task (configurable, default 60min) |

---

## Part 6: corvia v2 Architecture Reality

### What exists (4 MCP tools)

| Tool | Function |
|---|---|
| `corvia_search` | Semantic + BM25 hybrid search |
| `corvia_write` | Single entry write with auto-dedup (cosine ≥ 0.85) |
| `corvia_status` | System status |
| `corvia_traces` | Recent operation traces |

### What does NOT exist (referenced in AGENTS.md but aspirational)

`corvia_ask`, `corvia_context`, `corvia_graph`, `corvia_history`, `corvia_reason`,
`corvia_agent_status`, `corvia_gc_run`, `corvia_rebuild_index`, `corvia_config_get/set`,
`corvia_adapters_list`, `corvia_agents_list`, `corvia_merge_*`

Also missing: HTTP server, GC/TTL/decay, batch write, session/source metadata on entries,
adapter pattern, agent identity tracking.

### Storage model

- **Entries**: flat `.md` files in `.corvia/entries/` with TOML frontmatter
- **Metadata per entry**: `id` (UUIDv7), `created_at`, `kind` (decision/learning/instruction/reference), `supersedes`, `tags`
- **Indexes**: Redb (vectors, chunk map, supersession tracking) + Tantivy (BM25)
- **Chunking**: sentence-boundary-aware, 512 max tokens, 64 overlap, code block preservation
- **Embedding**: fastembed in-process (nomic-embed-text-v1.5, 768d)

### Integration points for passive ingestion

**Immediate (no code changes)**: Use `corvia_write` via MCP. Tags field carries metadata:
`tags: ["session:abc123", "source:claude-code", "kind:ephemeral"]`

**Short-term additions** (~200-300 lines):
- `write_batch()` in write.rs (open indexes once, embed batch, commit once)
- `corvia_write_batch` MCP tool
- Optional `source_origin`/`session_id` fields on EntryMeta

**Medium-term**: Revive v1's tiered GC design with `last_accessed`, `access_count`, `tier`,
`retention_score`, `pinned` fields on EntryMeta.

---

## Part 7: Proposed Architecture — Transcript Observer

### Design: harness-agnostic sidecar service

```
┌─────────────────────────────────────────────────────┐
│  Any AI Coding Harness                               │
│  Claude Code | Codex | Cursor | Copilot | Aider     │
│                                                       │
│  Produces: session logs (JSONL, SQLite, Markdown)    │
└──────────────────────┬────────────────────────────────┘
                       │ filesystem (append-only or db)
                       ▼
┌──────────────────────────────────────────────────────┐
│  corvia-observer (sidecar daemon)                     │
│                                                       │
│  Watchers:                                            │
│    inotify → JSONL files (Claude Code, Codex)        │
│    polling → SQLite files (Cursor, Copilot)           │
│    file-close → Markdown (Aider)                      │
│                                                       │
│  Per-file checkpoints:                                │
│    { path → (byte_offset, last_uuid, timestamp) }    │
│                                                       │
│  Harness adapters:                                    │
│    claude-code.rs → JSONL parser                      │
│    codex.rs → JSONL parser (different schema)         │
│    cursor.rs → SQLite vscdb parser                    │
│    aider.rs → Markdown parser                         │
│    generic.rs → line-by-line text                     │
│                                                       │
│  Processing pipeline:                                 │
│    1. Parse → unified SessionEvent                    │
│    2. Turn boundary detection                         │
│    3. Chunk (message-level or turn-level)             │
│    4. Classify kind (heuristic or LLM)                │
│    5. Assign decay tier (ephemeral by default)        │
│    6. UUID-based dedup                                │
│    7. Write to corvia                                 │
│                                                       │
│  Modes:                                               │
│    --streaming  (process as log grows)                │
│    --batch      (process on session end)              │
│    --hybrid     (stream + reconcile on end)           │
└──────────────────────┬────────────────────────────────┘
                       │ corvia_write / corvia_write_batch
                       ▼
┌──────────────────────────────────────────────────────┐
│  corvia knowledge store                               │
│                                                       │
│  Ephemeral tier:  session chunks (TTL: 7 days)       │
│  Learning tier:   extracted insights (TTL: 30 days)  │
│  Decision tier:   arch decisions (permanent)          │
│                                                       │
│  Consolidation (periodic background task):            │
│    - Merge similar ephemeral entries                  │
│    - Promote frequently-accessed to learning          │
│    - GC entries below retention threshold             │
│                                                       │
│  Exposed via: MCP (stdio) to any agent               │
└──────────────────────────────────────────────────────┘
```

### Two extraction modes

**Heuristic (fast, no LLM, default)**:
- Extract tool commands, file paths, error messages, git operations
- Detect decisions via keyword patterns (decided, chose, because, instead of)
- Tag with session metadata from the log envelope
- Cost: embedding only (~$0.001 per session)

**LLM-powered (richer, opt-in)**:
- Summarize each turn into a structured insight
- Classify kind with higher accuracy
- Extract entities and relationships
- Cost: ~$0.01-0.05 per session depending on length

### Chunking strategy

- **Primary unit**: Turn boundaries (user prompt → tool calls → assistant response)
- **Why turn-level**: Captures complete reasoning cycles. MemMachine showed only +0.8%
  accuracy gain from sentence-level over message-level, so finer granularity has diminishing
  returns.
- **Code handling**: Extract file paths and code snippets as metadata on the turn chunk.
  Do not embed raw code as standalone chunks (lacks semantic meaning without context).
- **Large turns**: If a turn exceeds 512 tokens, apply corvia's existing sentence-boundary
  chunker with overlap.

### Hot → permanent promotion path

```
Session ends → observer writes chunks as kind:ephemeral (TTL: 7 days)
                    │
                    ▼
Agent retrieves chunk via corvia_search → access_count++, last_accessed updated
                    │
                    ▼
Consolidation pass (daily):
  - If access_count >= 3 → promote to kind:learning (TTL: 30 days)
  - If similar chunks from multiple sessions → merge, promote to kind:learning
  - If explicitly confirmed by user → promote to kind:decision (permanent)
  - If access_count == 0 after TTL → GC (supersede, keep .md file for git history)
```

---

## Part 8: Open Questions

1. **Should the observer be a corvia subcommand (`corvia observe`) or a separate binary?**
   Subcommand keeps deployment simple. Separate binary allows independent release cycles.

2. **LLM extraction: local small model or cloud API?**
   Local (e.g., Qwen2.5-3B) is cheaper but requires GPU. Cloud is simpler but has latency
   and cost. Could be configurable.

3. **How to handle multi-agent sessions?**
   Claude Code spawns subagents. The JSONL log contains all subagent output. Should the
   observer track agent identity or treat the session as one unit?

4. **Consolidation vs. corvia's existing auto-dedup?**
   Auto-dedup (cosine >= 0.85) already prevents exact duplicates. Consolidation would handle
   the case where 5 sessions discuss the same topic differently — merge into one entry.

5. **What about security-sensitive content?**
   Session logs may contain secrets, credentials, or PII. The observer needs a filter/scrub
   step before writing to corvia. Could be a configurable deny-list of patterns.

---

## Sources

### Papers
- Mem0: arxiv 2504.19413 (ECAI 2025)
- MemGPT: arxiv 2310.08560
- Zep/Graphiti: arxiv 2501.13956
- MemMachine: arxiv 2604.04853
- xMemory: arxiv 2602.02007
- FadeMem: arxiv 2601.18642
- Nurture-First: arxiv 2603.10808
- AI Knowledge Assist: arxiv 2510.08149
- SGMem: arxiv 2509.21212
- AgentTrace: arxiv 2602.10133
- AGENTIF benchmark: Tsinghua (keg.cs.tsinghua.edu.cn)
- Instruction-following reliability: arxiv 2512.14754

### Tools & Projects
- Mem0: mem0.ai / github.com/mem0ai/mem0
- Letta: docs.letta.com
- LangMem: github.com/langchain-ai/langmem
- Zep: getzep.com
- Screenpipe: github.com/screenpipe/screenpipe
- Khoj: github.com/khoj-ai/khoj
- obsidian-mcp-server: github.com/cyanheads/obsidian-mcp-server
- mcp-memory-service (doobidoo): github.com/doobidoo/mcp-memory-service
- claude-mem: github.com/thedotmack/claude-mem
- session-graph: github.com/robertoshimizu/session-graph
- crune: github.com/chigichan24/crune
- Severance: github.com/blas0/Severance
- cursor-db-mcp: github.com/TaylorChen/cursor-db-mcp
- YourMemory (Ebbinghaus MCP): dev.to/sachit_mishra
- Hippo-Memory: github.com/kitfunso/hippo-memory
- SuperLocalMemory V3.3: arxiv 2604.04514

### Harness Session Formats
- Claude Code JSONL: code.claude.com/docs/en/hooks (SessionEnd provides transcript_path)
- Codex CLI: github.com/openai/codex (--json flag, rollout files)
- Copilot CLI: docs.github.com/en/copilot (events.jsonl + workspace.yaml)
- Cursor: SQLite vscdb, composerData keys (forum.cursor.com/t/chat-history-folder/7653)
- Gemini CLI: geminicli.com/docs/cli/session-management
- Aider: .aider.chat.history.md (aider.chat/docs/faq.html)

### Log Shipping / Sidecar Patterns
- Vector.dev file source: vector.dev/docs/reference/configuration/sources/file/
- notify-rs (inotify): github.com/notify-rs/notify
- MCP Streamable HTTP: modelcontextprotocol.io/specification

### Decay & GC Research
- FadeMem analysis: arxiv 2601.18642
- Memory triage for AI agents: fazm.ai/blog/ai-agent-memory-triage-retention-decay
- Cache eviction applied to knowledge: LRU + priority decay recommended as starting point
- ~71% of memories score below retention after 30 days (Fazm study)

### Claude Code Specific
- Hooks guide: code.claude.com/docs/en/hooks-guide
- Memory docs: code.claude.com/docs/en/memory
- PreToolUse additionalContext: github.com/anthropics/claude-code/issues/15345
- PostToolUse MCP bug: github.com/anthropics/claude-code/issues/24788
- Skills reliability: 650-trial study, 20x activation improvement with directive language
- Auto Dream: claudefa.st/blog/guide/mechanics/auto-dream
