# Corvia Benchmarking Design — 2026-03-19

> How corvia should benchmark itself, informed by best-in-class LLMOps tools.
> Key principle: dogfood corvia's own capabilities for evaluation.

## Landscape (2026)

### RAG Evaluation Frameworks

| Tool | Stars | Approach | Key Metrics | Corvia Fit |
|------|-------|----------|-------------|------------|
| **RAGAS** | ~25K | LLM-as-judge for RAG pipelines | Faithfulness, Answer Relevancy, Context Precision/Recall | High — can evaluate corvia_ask output |
| **DeepEval** | ~14K | Unit test framework for LLMs | 14+ metrics including hallucination, bias | Medium — more suited for chat, less for knowledge retrieval |
| **Arize Phoenix** | ~10K | Observability + evals | Trace analysis, retrieval quality | High — aligns with corvia's OTEL tracing |
| **Braintrust** | SaaS | Experiment tracking, scoring | Custom scorers, A/B testing | Low — SaaS, not self-hostable |
| **Promptfoo** | ~11K | CLI eval runner | Custom assertions, red-teaming | Medium — good CI/CD integration patterns |

### Embedding Benchmarks

| Benchmark | Scope | Metrics |
|-----------|-------|---------|
| **MTEB** | Massive Text Embedding Benchmark | 56 datasets, 8 tasks (retrieval, classification, etc.) |
| **BEIR** | Information Retrieval | NDCG@10, Recall@100 across 18 datasets |
| **Domain-specific** | Custom eval sets | Recall@K, MRR, precision on own data |

### Key Insight: Eval-Driven Development

From Hamel Husain (LLM reliability guru) and Jason Liu (instructor):
- **Evals are tests, not benchmarks** — run them on every PR
- **Start with assertion-based evals** — expected keywords, source matching
- **Graduate to LLM-as-judge** — for semantic quality assessment
- **Track over time** — regression detection is more valuable than absolute scores

## Corvia's Unique Dogfooding Advantage

Corvia can benchmark itself using its own knowledge base — no synthetic data needed:

1. **Knowledge entries as ground truth**: 8,769 entries with known sources, content, and relationships
2. **Graph edges as expected relationships**: 11,756 edges define what should be related
3. **Temporal history as regression data**: Supersession chains show how knowledge evolved
4. **OTEL traces as latency data**: DashboardTraceLayer captures real timing
5. **Reasoner as quality oracle**: Health checks detect inconsistencies programmatically

## Eval Suite Architecture

```
benchmarks/
├── rag-retrieval/
│   ├── eval-queries.json     # Known-answer query set (15 queries)
│   ├── eval.py               # Python eval runner (REST API)
│   └── results/              # Timestamped JSON results
├── embedding-models/
│   ├── run.sh                # Latency/throughput benchmark
│   └── results/
├── knowledge-health/
│   ├── eval.py               # Graph consistency, temporal accuracy
│   └── results/
└── ci/
    └── eval-gate.sh          # CI script: fail if metrics regress
```

### Tier 1: Assertion-Based (run on every build)

**What**: Keyword and source matching against known-answer queries.
**How**: `benchmarks/rag-retrieval/eval.py` (already built)
**Metrics**: Source Recall@K, Keyword Recall, MRR
**Baseline**: Recall@5=37.5%, KW=65%, MRR=0.544 (2026-03-19)
**Regression gate**: Fail if Recall@5 drops below 30% or MRR below 0.4

### Tier 2: Knowledge Health (run daily)

**What**: Use corvia's own reasoner to check knowledge base consistency.
**How**: `POST /v1/reason` → count findings, track over time
**Metrics**: Finding count by type, coverage gaps, contradiction rate
**Dogfooding**: corvia's reasoner evaluates corvia's own knowledge

### Tier 3: LLM-as-Judge (run weekly or on release)

**What**: Use corvia_ask to generate answers, then judge quality with LLM.
**How**: Ask known questions → get AI answer → LLM scores answer quality
**Metrics**: Faithfulness, completeness, hallucination rate
**Dogfooding**: corvia_ask generates answers from its own knowledge → LLM judges

### Tier 4: Comparative (run on model/config changes)

**What**: Compare retrieval with/without graph expansion, different models, etc.
**How**: A/B eval runs with different configs
**Metrics**: Delta in Recall@K, latency, cost
**Dogfooding**: Same queries, different corvia configs

## Implementation Priority

1. **DONE**: Tier 1 eval suite with real baseline numbers
2. **NEXT**: CI eval gate script (`eval-gate.sh`)
3. **NEXT**: Tier 2 knowledge health tracking
4. **LATER**: Tier 3 LLM-as-judge (requires chat inference stability)
5. **LATER**: Tier 4 comparative evals

## Comparison with Competitors

| Feature | Corvia | RAGAS | DeepEval | Arize Phoenix |
|---------|--------|-------|----------|---------------|
| Self-benchmarking | Yes (dogfooding) | No (external data) | No | No |
| Built-in knowledge graph | Yes | No | No | No |
| OTEL integration | Yes (native) | No | No | Yes |
| Rust-native | Yes | No (Python) | No (Python) | No (Python) |
| Temporal quality checks | Yes | No | No | No |
| Assertion-based | Yes | Partial | Yes | No |
| LLM-as-judge | Planned | Yes | Yes | Yes |

**Corvia's differentiator**: No other tool evaluates its own knowledge quality using
its own retrieval pipeline. The eval suite IS the product — dogfooding at its best.

---

*Reviewed by: SWE (sound architecture, tier system is pragmatic), PM (dogfooding angle is compelling for LinkedIn), QA (baseline numbers provide regression detection)*
