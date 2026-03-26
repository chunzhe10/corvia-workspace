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

## Retrieval Quality A/B Test

Compare retrieval quality (not just latency) between embedding models:

```bash
bash benchmarks/embedding-models/ab-test-retrieval.sh
```

This orchestrator:
1. Runs the full eval suite with the current model (nomic-embed-text-v1.5)
2. Switches to all-MiniLM-L6-v2 (384d), restarts servers, re-ingests
3. Runs the eval suite again
4. Restores original config and produces a comparison report

**Runtime**: Several minutes (two full ingestion cycles). Not suitable for CI.

To compare results manually:

```bash
python3 benchmarks/embedding-models/compare-models.py \
    results/model-nomic-embed-text-v1.5-*.json \
    results/model-all-MiniLM-L6-v2-*.json \
    --model-a nomic-embed-text-v1.5 --model-b all-MiniLM-L6-v2 \
    --persist  # optional: save findings to corvia
```

### Key Insight

From the project's memory: **RAG retrieval is 89% of pipeline latency**.
Optimizing the embedding model has diminishing returns — focus on retrieval
strategy (graph expansion, post-filtering) for the biggest impact.
