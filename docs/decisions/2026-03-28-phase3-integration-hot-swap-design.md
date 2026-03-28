# Phase 3: Integration + Hot-Swap Design

**Issue:** chunzhe10/corvia#42
**Parent:** chunzhe10/corvia#37
**Date:** 2026-03-28
**Status:** Approved (design from RFC, validated against current codebase)

## Overview

Wire ArcSwap hot-swap, config hot-reload, graceful degradation, cold tier rescue,
and end-to-end hybrid search integration into the composable pipeline.

## Design Decisions (validated against current code)

### D9: ArcSwap Hot-Swap

**Current state:** `AppState.rag` is `Option<Arc<RagPipeline>>`. The RAG pipeline is
constructed once at startup via `create_rag_pipeline()` and never rebuilt.

**Change:** Wrap `RagPipeline` in `ArcSwap` so that `config_set` on `rag.pipeline.*`
triggers a rebuild + atomic swap.

- `AppState.rag` becomes `Arc<ArcSwap<Arc<RagPipeline>>>`
- Add `validate_and_build()` to `PipelineRegistry` that validates config and builds
  a complete pipeline, returning `Result<RetrievalPipeline>`
- On `config_set` for `rag.pipeline.*`: validate_and_build -> swap. Invalid config
  rejects with warning, old pipeline continues.
- Snapshot isolation: in-flight requests complete on the old pipeline.

### D12: Graceful Degradation

**Current state:** `core.rs` already handles timeout + panic isolation via
`tokio::spawn` per searcher. But:
1. Embedding failure causes total pipeline failure (no BM25 fallback)
2. All searchers failing returns empty results (should be an error)
3. Per-searcher BM25 metrics not tracked

**Changes:**
1. Embedding failure path: if embedding fails AND BM25 searcher is configured,
   skip vector search and proceed with BM25-only (set `needs_embedding` flag per searcher)
2. All searchers fail: return `PipelineError::AllSearchersFailed`
3. Track bm25_latency_ms and bm25_results in RetrievalMetrics

### D13: Cold Tier Interaction

**Current state:** VectorSearcher uses `store.search()` which respects HNSW indexing
(cold entries not in HNSW). BM25Searcher uses `fts.search()` which searches all
indexed tantivy documents (including cold entries).

**Verification needed:** Confirm BM25 does NOT filter by tier, so cold entries surface.
When cold entry is returned via BM25, access recording triggers tier promotion.

### D14: MCP Tool Behavior

**Current state:** All MCP tools (corvia_search, corvia_context, corvia_ask) route
through `RagPipeline` which calls `Retriever::retrieve()`. `RetrievalPipeline`
implements `Retriever`. Score field is `final_score` (normalized [0,1]).

**Change:** None. Verify all tools work end-to-end with hybrid search. No response
format changes.

### Integration Tests

Full test suite per issue #42 checklist:
- Hybrid search: vector + BM25 + RRF + graph on test dataset
- Graceful degradation: FailingSearcher + working searcher
- Timeout: SlowSearcher with timeout
- Panic: PanicSearcher
- Hot-swap under load: concurrent queries during swap
- Cold tier rescue: cold entry found by BM25, promoted
- Config validation: invalid combo rejected

## Files to Modify

1. `crates/corvia-server/src/rest.rs` - AppState.rag -> ArcSwap
2. `crates/corvia-server/src/mcp.rs` - config_set handler triggers pipeline rebuild
3. `crates/corvia-kernel/src/pipeline/core.rs` - embedding failure degradation, all-fail error, metrics
4. `crates/corvia-kernel/src/pipeline/registry.rs` - validate_and_build()
5. `crates/corvia-kernel/src/lib.rs` - expose build_pipeline_retriever as pub, rebuild helper
6. `crates/corvia-kernel/src/pipeline/mod.rs` - PipelineError::AllSearchersFailed
7. `crates/corvia-kernel/src/pipeline/core.rs` - integration tests
