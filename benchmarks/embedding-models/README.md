# Embedding Model Benchmarks

## Existing Results

A comprehensive GPU backend benchmark was already conducted on 2026-03-16.
See the full report: [`docs/benchmarks/embedding-backend-benchmark.md`](../../docs/benchmarks/embedding-backend-benchmark.md)

### Summary (nomic-embed-text-v1.5, 768d)

| Backend | Latency (ms/embed) | Throughput | Speedup vs CPU |
|---------|-------------------|------------|----------------|
| CPU | 215ms | 4.7/s | 1.0x |
| OpenVINO (iGPU) | 51ms | 19.8/s | 4.21x |
| CUDA (dGPU) | 56ms | 17.8/s | 3.81x |

**Finding**: Intel iGPU slightly faster than NVIDIA dGPU for embedding due to
zero-copy shared memory vs PCIe transfer overhead. Default config uses OpenVINO
for embedding, CUDA for chat.

## Additional Benchmarks

### Search Latency (embed + HNSW retrieval)

Run `bash run.sh` to measure end-to-end search latency across text lengths.
This includes embedding time + HNSW search + graph expansion.

### Model Comparison

| Model | Dimensions | Size | Notes |
|-------|-----------|------|-------|
| nomic-embed-text-v1.5 | 768 | 137M params | Default, best quality |
| all-MiniLM-L6-v2 | 384 | 22M params | Lightweight, 6x smaller |

Both models are supported by corvia-inference. Switch via `corvia.toml`:
```toml
[inference]
embedding_model = "all-MiniLM-L6-v2"  # or "nomic-embed-text-v1.5"
```

### Key Insight

From the project's memory: **RAG retrieval is 89% of pipeline latency**.
Optimizing the embedding model has diminishing returns — focus on retrieval
strategy (graph expansion, post-filtering) for the biggest impact.
