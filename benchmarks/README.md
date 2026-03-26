# Corvia Benchmarks

Reproducible benchmarks for evaluating corvia's core capabilities.

## Structure

```
benchmarks/
├── ci/                   # CI quality gates (eval-gate, health-gate, PR comment formatters)
├── embedding-models/     # Embedding model comparison (latency, accuracy, A/B retrieval quality)
├── knowledge-health/     # Knowledge base health tracking (structural integrity checks)
├── rag-retrieval/        # RAG pipeline retrieval quality (precision, recall, relevance, A/B)
├── chunking-strategies/  # Chunking approach comparison (format-aware vs fixed-size vs semantic)
└── README.md             # This file
```

## Running Benchmarks

Each benchmark directory contains:
- `README.md` — methodology, setup, and results
- `run.sh` or `run.py` — reproducible benchmark script
- `results/` — output data (JSON, CSV)

### Prerequisites

- corvia server running (`corvia-dev up`)
- Inference server running (port 8030)
- Knowledge base populated (`corvia workspace ingest`)

## Benchmark Categories

### 1. Embedding Models
Compare embedding models on corvia's workload:
- nomic-embed-text-v1.5 (768d, default)
- all-MiniLM-L6-v2 (384d, lightweight)

Metrics: latency (ms/embed), throughput (embeds/s), memory usage, retrieval quality (recall@k)

### 2. RAG Retrieval
Evaluate retrieval quality using corvia's own knowledge base as ground truth:
- Vector-only retrieval vs graph-expanded retrieval
- Different top-k values
- Scope filtering impact
- Post-filter effectiveness

Metrics: precision@k, recall@k, MRR, latency

### 3. Chunking Strategies
Compare chunking approaches:
- Format-aware (current: AST + markdown sections)
- Fixed-size token windows
- Semantic chunking (paragraph boundaries)

Metrics: retrieval relevance, chunk size distribution, embedding efficiency
