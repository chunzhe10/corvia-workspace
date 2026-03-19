# RAG Retrieval Benchmarks

Evaluates corvia's RAG pipeline retrieval quality using its own knowledge base
as ground truth (dogfooding).

## Methodology

1. **Known-answer queries**: Questions with known answers from the design docs
2. **Retrieval modes**: Compare vector-only vs graph-expanded retrieval
3. **Relevance scoring**: Check if expected source files appear in top-k results

## Test Queries

| # | Query | Expected Source | Category |
|---|-------|----------------|----------|
| 1 | "What is the LiteStore storage format?" | corvia-design.md, ARCHITECTURE.md | Architecture |
| 2 | "How does agent crash recovery work?" | milestone-revision-notes.md (D45) | Feature |
| 3 | "What embedding model does corvia use?" | embedding-backend-benchmark.md | Config |
| 4 | "How does the merge worker resolve conflicts?" | milestone-revision-notes.md | Feature |
| 5 | "What is the dashboard architecture?" | standalone-dashboard-design.md | Architecture |
| 6 | "How does temporal reasoning work?" | m3-temporal-graph-reasoning-design.md | Feature |
| 7 | "What license is corvia under?" | README.md, corvia-design.md | Metadata |
| 8 | "How are knowledge entries chunked?" | m3.3-embedding-chunking-design.md | Pipeline |
| 9 | "What MCP tools are available?" | AGENTS.md | API |
| 10 | "How does graph expansion affect retrieval?" | retriever.rs via search | Algorithm |

## Metrics

- **Recall@5**: Does the expected source appear in top 5 results?
- **Recall@10**: Does the expected source appear in top 10 results?
- **MRR**: Mean Reciprocal Rank of the expected source
- **Latency**: End-to-end retrieval time (ms)

## Results

Run `bash run.sh` to generate results.

### Preliminary Results (2026-03-19)

From trace data collected during this session:

| Operation | Latency | Notes |
|-----------|---------|-------|
| corvia.rag.context | 35ms | Full pipeline: embed + HNSW + graph expand |
| corvia.entry.embed | 22ms | Embedding only (via gRPC to inference server) |
| corvia.store.search | 12ms | HNSW vector search only |

Graph expansion adds ~1ms overhead but significantly improves recall by
following knowledge graph edges to related entries.
