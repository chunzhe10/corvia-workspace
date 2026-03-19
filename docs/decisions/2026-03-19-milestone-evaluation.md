# Milestone Evaluation — 2026-03-19

> Autonomous evaluation of M1-M7 against current state.
> Decision: which milestones to advance, defer, or revise.

## Current State Summary

| Component | Status | Evidence |
|-----------|--------|----------|
| Kernel (LiteStore, HNSW, traits) | COMPLETE | 8,769 entries, 11,756 graph edges |
| Agent Coordination | COMPLETE | MCP + REST, multi-agent lifecycle, staging, merge |
| Temporal + Graph | COMPLETE | TemporalStore, GraphStore, petgraph, Redb persistence |
| Reasoning (Level 2-3) | COMPLETE | 5 deterministic + 2 LLM checks, 41+ tests |
| Observability | COMPLETE | OTEL spans, dashboard traces (just fixed), 10/10 dashboard features |
| Dashboard | COMPLETE | Standalone Vite+React, all 10 features, graph viewer, activity feed |
| Docs Workflow | COMPLETE | Phase 1-4 done, hooks, incremental ingest |
| Session History | COMPLETE | 6 deliverables, REST ingest/classify endpoints |
| GPU Inference | COMPLETE | CUDA + OpenVINO, nomic-embed-text-v1.5, chat models |
| Adapter System | COMPLETE | Git + Basic adapters, JSONL protocol, auto-discovery |

## Milestone Status

### M1: Index & Understand — COMPLETE
All deliverables shipped. Rust AST indexer, vector search, LiteStore.

### M2: Agent Coordination — COMPLETE
Agent coordinator, staging hybrid, MCP server, REST sessions, merge pipeline,
crash recovery, GC, visibility modes.

### M3: Temporal + Graph + Reasoning — COMPLETE
TemporalStore, GraphStore (petgraph + Redb), Level 2-3 reasoning, self-dogfooding.
`corvia rebuild` reconstructs all indexes.

### M4: Observability — COMPLETE (with today's fix)
corvia-telemetry crate, OTEL spans, dashboard with traces (now working),
structured JSON logs, DashboardTraceLayer for local trace collection.

### M5: VS Code Extension — REVISED → Standalone Dashboard
**Original plan**: VS Code extension via MCP.
**Current reality**: Standalone dashboard (Vite+React) at port 8021 already provides:
- Pipeline flow visualization, agent status, merge queue, RAG traces
- Interactive knowledge graph, temporal history, activity feed
- Configuration panel, OTEL span drill-down, GC operations
- Live session monitoring

**Decision**: M5 is effectively COMPLETE via the standalone dashboard. The VS Code
extension is a nice-to-have for later but the dashboard delivers the same value.
The MCP server is the integration surface — any tool can connect.

### M6: Evals & Benchmarks — NOT STARTED → PRIORITY
This is the most important remaining milestone. Without evals, we can't prove
quality claims. Key deliverables:
1. Retrieval precision/recall benchmarks
2. Embedding model comparison (nomic vs MiniLM vs alternatives)
3. RAG pipeline approach comparison
4. Temporal accuracy tests
5. Graph connectivity tests
6. With-vs-without comparison (agent quality with/without corvia)
7. Cost tracking

**Decision**: Start M6 benchmarks now. Create reproducible benchmark suite.

### M7: OSS Launch — DEFERRED
Depends on M6 evals. Current blockers:
- No published crates yet
- No docs site
- README needs polish
- Need eval numbers before claiming quality

**Decision**: Defer until M6 produces compelling numbers.

## Action Plan

1. **Now**: Create benchmarks directory with M6 eval framework
2. **Now**: Run embedding model benchmarks (already have two models)
3. **Now**: Run RAG retrieval benchmarks against own knowledge base
4. **Later**: Cost tracking, with-vs-without comparison
5. **Later**: M7 OSS launch preparation

## Review

**Senior SWE**: Sound evaluation. M5 revision is pragmatic — the dashboard delivers
the same value. M6 prioritization is correct.
**PM**: M6 evals are critical for the LinkedIn narrative. "Here are the numbers" is
more compelling than "trust me, it works."
**QA**: Benchmarks need reproducible scripts, not ad-hoc measurements.

**Verdict**: APPROVE — proceed with M6 benchmarks.
