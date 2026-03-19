# RAG Layer Abstraction Plan

> **Status**: Active
> **Goal**: Make RAG pipeline components config-driven and swappable at runtime,
> like the adapter system.

## Current State

The RAG pipeline already has trait-based abstraction:
```
RagPipeline
├── Retriever (trait) — VectorRetriever, GraphExpandRetriever
├── Augmenter (trait) — StructuredAugmenter
└── GenerationEngine (trait) — GrpcChatEngine, OllamaChatEngine
```

But component selection is **hardcoded at build time** in `main.rs` / server setup:
- `graph_expand = true` toggles between two retrievers
- Only one augmenter exists (StructuredAugmenter)
- No way to add external retriever/augmenter plugins

## Target State

Config-driven RAG pipeline where components are selected by name:
```toml
[rag]
retriever = "graph_expand"    # or "vector", "hybrid", "custom"
augmenter = "structured"      # or "minimal", "citation_rich"
generation = "grpc"           # or "ollama", "none"
```

## Design

### Phase 1: Config-Driven Selection (lightweight, no plugin system)

Add a `RagComponentRegistry` that maps config names to trait implementations:

```rust
pub struct RagComponentRegistry {
    retrievers: HashMap<String, Arc<dyn Fn(/* deps */) -> Arc<dyn Retriever>>>,
    augmenters: HashMap<String, Arc<dyn Fn() -> Arc<dyn Augmenter>>>,
}

impl RagComponentRegistry {
    pub fn new() -> Self { /* register built-in components */ }
    pub fn build_pipeline(&self, config: &RagConfig) -> RagPipeline { ... }
}
```

This is the adapter pattern applied to RAG — same as how adapters are discovered
by name and instantiated from config.

### Phase 2: Additional Retrievers (future)

| Retriever | Description | When |
|-----------|-------------|------|
| `vector` | Pure HNSW vector search (existing) | Built-in |
| `graph_expand` | Vector + graph expansion (existing) | Built-in |
| `hybrid` | BM25 + vector fusion (new) | After adding BM25 index |
| `reranker` | Vector + cross-encoder reranking (new) | After adding reranker model |
| `temporal` | Time-weighted retrieval (new) | After temporal scoring |

### Phase 3: External RAG Plugins (future)

Like the adapter JSONL protocol, allow external retriever processes:
```
corvia-retriever-bm25 → JSONL IPC → corvia kernel
```

## Implementation Tasks

1. Add `retriever = "graph_expand"` to `[rag]` config
2. Add `augmenter = "structured"` to `[rag]` config
3. Create `RagComponentRegistry` in `rag_pipeline.rs`
4. Refactor pipeline construction to use registry + config
5. Update server/CLI to use registry
6. Add tests for config-driven pipeline selection
7. Update ARCHITECTURE.md

## Review

**Senior SWE**: The traits already exist — this is just adding a config-driven
factory pattern on top. Low risk, high value for benchmarking (swap retrievers
for A/B testing). APPROVE.

**PM**: Config-driven RAG selection enables the M6 comparative eval (Tier 4).
Users can experiment with different strategies without code changes. APPROVE.

**QA**: Must verify all existing tests pass after refactor. The factory must
default to current behavior (`graph_expand`). APPROVE.

**Verdict**: APPROVE — proceed with Phase 1.
