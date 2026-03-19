# CI Quality Gate — RAG Retrieval

Automated quality gate that runs corvia's RAG retrieval eval suite and
enforces minimum metric thresholds. Designed to run in CI or locally
before merging changes that affect retrieval quality.

## Usage

```bash
# Default: server at localhost:8020, top-10 retrieval
./benchmarks/ci/eval-gate.sh

# Override server URL or eval limit
CORVIA_SERVER=http://localhost:8020 EVAL_LIMIT=15 ./benchmarks/ci/eval-gate.sh
```

## What it does

1. **Health check** — verifies the corvia server is reachable at `/health`
2. **Run eval suite** — executes `benchmarks/rag-retrieval/eval.py` with
   known-answer queries against the live server
3. **Parse results** — reads the latest `eval-*.json` from the results directory
4. **Check thresholds** — compares metrics against minimum requirements

## Thresholds

| Metric | Threshold | Rationale |
|--------|-----------|-----------|
| MRR (Mean Reciprocal Rank) | >= 0.40 | Relevant results should appear in top 3 on average |
| Source Recall@5 | >= 0.25 | At least 1 in 4 expected sources found in top 5 |
| Keyword Recall | >= 0.50 | At least half of expected keywords present |
| Query Timeouts | <= 3 | No more than 3 queries may time out |

These thresholds are set conservatively based on the baseline measurement
(2026-03-19: MRR 0.54, Source Recall@5 0.38, Keyword Recall 0.65). They
represent a floor below which retrieval quality is unacceptable, not a target.

## Exit codes

- **0** — all thresholds met
- **1** — one or more thresholds breached, or the server is unreachable

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CORVIA_SERVER` | `http://localhost:8020` | Server URL |
| `EVAL_LIMIT` | `10` | Top-K results per query |

## Prerequisites

- corvia server running (API + inference)
- Python 3 available on PATH
- Knowledge base ingested (`corvia workspace ingest`)
