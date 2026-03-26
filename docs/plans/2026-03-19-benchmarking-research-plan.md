# Benchmarking & Eval Implementation Plan

> **Status**: Active
> **Priority**: P0 (blocks M6 milestone and M7 OSS launch)
> **Dependencies**: RAG abstraction (DONE), traces fix (DONE), eval baseline (DONE)

## Background

Research completed on 2026-03-19 covering RAGAS, DeepEval, MTEB, Cognee, Langfuse,
and eval-driven development methodologies from Hamel Husain and Jason Liu.

Full research: `docs/decisions/2026-03-19-llmops-benchmarking-research.md`

## Phase 1: Assertion-Based Evals (DONE)

- [x] Known-answer query set (15 queries, 5 categories, 3 difficulty levels)
- [x] Python eval runner using REST API
- [x] Metrics: Source Recall@K, Keyword Recall, MRR, relevance score
- [x] Baseline established: Recall@5=37.5%, KW=65%, MRR=0.544

## Phase 2: CI Quality Gate (DONE)

- [x] Create `benchmarks/ci/eval-gate.sh`
- [x] Run eval suite on PRs touching retrieval/RAG code
- [x] Fail if MRR drops below 0.4 or Recall@5 drops below 30%
- [x] Report results as PR comment (via `gh` CLI)
- [x] Add to GitHub Actions (`.github/workflows/eval-gate.yml`)

## Phase 3: Knowledge Health Tracking

- [ ] Create `benchmarks/knowledge-health/eval.py`
- [ ] Use `POST /v1/reason` to count findings by type
- [ ] Track over time: stale entries, broken chains, contradictions
- [ ] Persist results as corvia knowledge entries (dogfooding)
- [ ] Dashboard panel for health trends

## Phase 4: Jason Liu's 6 RAG Evals (Rust-native)

- [ ] Implement C|Q (Context Relevance) — uses embedding similarity
- [ ] Implement A|C (Answer Faithfulness) — uses LLM-as-judge
- [ ] Implement A|Q (Answer Relevance) — uses LLM-as-judge
- [ ] Build `corvia bench` CLI command
- [ ] Binary pass/fail first, graded scores later
- [ ] Store eval results as knowledge entries (dogfooding)

## Phase 5: Comparative Evals

- [ ] A/B test: `retriever = "vector"` vs `retriever = "graph_expand"`
- [ ] A/B test: nomic-embed-text-v1.5 vs all-MiniLM-L6-v2
- [ ] Measure delta in Recall@K, latency, cost per query
- [ ] Requires RAG config abstraction (DONE — Phase 1 shipped)

## Phase 6: `corvia bench` Product Feature

- [ ] `corvia bench run` — runs full eval suite against local knowledge
- [ ] `corvia bench report` — generates quality dashboard
- [ ] `corvia bench compare` — A/B comparison between configs
- [ ] Publish as a product feature in README

## Key Metrics to Track

| Metric | Target | Current Baseline |
|--------|--------|-----------------|
| Source Recall@5 | >60% | 37.5% |
| Keyword Recall | >80% | 65% |
| MRR | >0.7 | 0.544 |
| Avg Latency | <100ms | 50ms (search) |
| P95 Latency | <500ms | 3082ms (outlier) |

## Research-Backed Decisions

1. **Jason Liu's 6 RAG evals over RAGAS** — minimal, complete, understandable
2. **Error analysis first over metric design** — Hamel Husain methodology
3. **Multi-metric with bootstrapping** — Cognee's approach for confidence intervals
4. **Rust-native over Python** — no mature Rust eval framework exists (opportunity)
5. **Dogfooding over synthetic data** — corvia evaluates itself using its own knowledge
