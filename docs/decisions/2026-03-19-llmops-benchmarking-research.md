# LLMOps Benchmarking Research — 2026-03-19

> Comprehensive research on best-in-class evaluation tools and approaches.
> Compiled from web research across RAGAS, DeepEval, MTEB, Cognee, Langfuse, and more.

## Top Frameworks Evaluated

| Tool | Stars | License | Best For | Corvia Fit |
|------|-------|---------|----------|------------|
| RAGAS | ~25K | Apache 2.0 | RAG-specific metrics, synthetic test generation | High |
| DeepEval | ~14K | Apache 2.0 | 50+ metrics, self-explaining scores, unit testing | High |
| Arize Phoenix | ~7K | Apache 2.0 | OTEL tracing, embedding drift | Medium |
| Langfuse | ~60K | MIT | Cost tracking, prompt versioning | Medium-High |
| Promptfoo | ~11K | MIT | CI/CD eval runner, red-teaming | Medium |

## Key Methodologies

### Jason Liu's 6 RAG Evals (Priority P0)
The minimal, complete evaluation surface for any RAG system:
1. Context Relevance (C|Q) — Is retrieved context relevant to the question?
2. Context Support (C|A) — Does context support the answer?
3. Answer Relevance (A|Q) — Does the answer address the question?
4. Answer Faithfulness (A|C) — Is the answer grounded in context?
5. Question Clarity (Q|C) — Is the question well-formed given context?
6. Question Coverage (Q|A) — Does the question capture what the answer provides?

### Hamel Husain's Error Analysis First (Priority P0)
1. Gather traces, review manually, note failures
2. Build failure taxonomy, count frequencies
3. Use binary pass/fail judgments
4. Write evaluators for discovered errors, not imagined ones
5. LLM-as-a-judge: error analysis → prompt iteration → labeled examples

### Cognee's Multi-Metric Approach (Priority P1)
- Combine EM + F1 + LLM-judge correctness
- 45 evaluation cycles per system with statistical bootstrapping
- Multi-metric prevents single-metric gaming

## Corvia-Specific Recommendations

### Phase 1: Foundation (Immediate)
- Build golden QA dataset from corvia's own knowledge base (50-100 questions)
- Implement Jason Liu's 6 RAG evals in Rust
- Track MRR, Recall@K, NDCG@10 natively

### Phase 2: Automated Pipeline
- Adopt Cognee's multi-metric + bootstrapping approach
- Add token-count tracking to corvia_ask for cost estimation
- CI quality gate: fail if MRR drops below threshold

### Phase 3: Differentiation
- Publish `corvia bench` command as a product feature
- Domain-specific MTEB evaluation on corvia's own data
- Contribute Rust-native eval crate (no mature one exists — opportunity)

## What NOT to Adopt
- TruLens — declining ecosystem post-Snowflake acquisition
- LangSmith — too LangChain-coupled
- Heavy Python eval stacks — corvia is Rust-native
- Arize Phoenix for eval — overkill for corvia's scale

## Competitive Differentiator
No other tool evaluates its own knowledge quality using its own retrieval pipeline.
corvia's eval suite IS the product — dogfooding at its best.

Sources: RAGAS docs, DeepEval GitHub, Cognee AI blog, Letta benchmarking blog,
Hamel Husain evals FAQ, Jason Liu's 6 RAG evals, PostHog dogfooding guide,
MMTEB paper, Braintrust articles, DEV Community comparisons.
