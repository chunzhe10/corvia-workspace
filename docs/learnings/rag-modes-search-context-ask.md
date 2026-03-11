# RAG Modes: search vs context vs ask

> Captured 2026-03-10. Decision on disabling ask/generation TBD.

## Overview

The RAG pipeline (`corvia-kernel/src/rag_pipeline.rs`) has three modes with
increasing cost and capability:

| | search | context | ask |
|---|---|---|---|
| **Stage 1: Retrieval** | Vector search | Vector search + optional graph expansion | Vector search + optional graph expansion |
| **Stage 2: Augmentation** | No | Yes — assembles sources into structured context with token budgets, skill injection | Same as context |
| **Stage 3: Generation** | No | No | Yes — sends assembled context to LLM for a synthesized answer |
| **Returns** | Raw matching entries with scores | Assembled context document + sources + trace | Context + LLM-generated answer + trace |
| **Requires LLM** | No | No | Yes (GenerationEngine) |

## Summary

- **`search`** — raw entries matching the query (cheapest, fastest)
- **`context`** — structured context assembled from retrieved entries (no LLM needed)
- **`ask`** — full RAG: context assembly + LLM-generated answer (requires GenerationEngine)

## RAM implications

- `search` and `context` only need the embedding model (for vector similarity)
- `ask` additionally needs a chat/generation model loaded, which is the main RAM cost
- The GenerationEngine is optional in `RagPipeline::new()` — passing `None` disables
  `ask()` gracefully (returns config error) while `context()` and search still work

## Open question

Can we add a config toggle (e.g., `generation_enabled = false` in `corvia.toml`) to
skip loading the chat model entirely, saving RAM while keeping search and context
functional? Currently there is no single config flag for this — disabling requires
either not providing a GenerationEngine in code or not running the inference server
(which also disables embeddings).
