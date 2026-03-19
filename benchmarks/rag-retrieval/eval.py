#!/usr/bin/env python3
"""
Corvia RAG Retrieval Evaluation Suite — Dogfooding Edition

Uses corvia's own MCP API to evaluate retrieval quality against known-answer
queries derived from corvia's own documentation and design decisions.

Metrics:
- Source Recall@K: Does the expected source file appear in top-K results?
- Keyword Recall: Do expected keywords appear in retrieved content?
- MRR (Mean Reciprocal Rank): Average 1/rank of first relevant result
- NDCG@10: Normalized Discounted Cumulative Gain (binary relevance)
- Precision@5: Fraction of top-5 results matching expected sources
- Precision@10: Fraction of top-10 results matching expected sources
- Latency: End-to-end retrieval time per query

Usage:
    python3 benchmarks/rag-retrieval/eval.py [--server http://localhost:8020] [--limit 10]
"""

import json
import math
import time
import sys
import argparse
from pathlib import Path
from urllib.request import urlopen, Request
from urllib.error import URLError

EVAL_QUERIES_PATH = Path(__file__).parent / "eval-queries.json"
RESULTS_DIR = Path(__file__).parent / "results"


def mcp_search(server: str, query: str, limit: int = 10, scope: str = "corvia") -> dict:
    """Call corvia search via REST API (v1/memories/search)."""
    payload = json.dumps({
        "query": query,
        "scope_id": scope,
        "limit": limit,
    }).encode()

    req = Request(f"{server}/v1/memories/search", data=payload, headers={"Content-Type": "application/json"})
    start = time.monotonic()
    try:
        with urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
            latency_ms = (time.monotonic() - start) * 1000
    except (URLError, TimeoutError) as e:
        return {"error": str(e), "latency_ms": 0, "results": []}

    # REST API returns array of search results directly
    results = data if isinstance(data, list) else data.get("results", [])
    return {"results": results, "latency_ms": latency_ms, "error": None}


def _is_result_relevant(result: dict, expected_sources: list[str]) -> bool:
    """Check if a single search result matches any expected source."""
    source = (result.get("source_file", "") or "").lower()
    return any(expected.lower() in source for expected in expected_sources)


def _compute_ndcg(relevance_list: list[int], k: int = 10) -> float:
    """Compute NDCG@k with binary relevance scores.

    relevance_list: list of 0/1 values for each result position.
    Returns 0.0 if there are no relevant results in the ideal ranking.
    """
    relevance_list = relevance_list[:k]

    # DCG: sum of rel_i / log2(i+2) for i in 0..k-1  (positions are 0-indexed)
    dcg = sum(rel / math.log2(i + 2) for i, rel in enumerate(relevance_list))

    # Ideal DCG: sort relevance descending, recompute
    ideal = sorted(relevance_list, reverse=True)
    idcg = sum(rel / math.log2(i + 2) for i, rel in enumerate(ideal))

    if idcg == 0:
        return 0.0
    return dcg / idcg


def _compute_precision_at_k(relevance_list: list[int], k: int) -> float:
    """Compute Precision@k: fraction of top-k results that are relevant."""
    top_k = relevance_list[:k]
    if not top_k:
        return 0.0
    return sum(top_k) / len(top_k)


def evaluate_query(query_def: dict, search_results: list, latency_ms: float) -> dict:
    """Evaluate a single query against expected results."""
    result = {
        "id": query_def["id"],
        "query": query_def["query"],
        "category": query_def["category"],
        "difficulty": query_def["difficulty"],
        "latency_ms": round(latency_ms, 1),
        "result_count": len(search_results),
    }

    # Source Recall: check if expected source files appear in results
    expected_sources = query_def.get("expected_sources", [])
    source_found_at = {}
    for i, r in enumerate(search_results):
        source = (r.get("source_file", "") or "").lower()
        for expected in expected_sources:
            if expected.lower() in source and expected not in source_found_at:
                source_found_at[expected] = i + 1  # 1-indexed rank

    result["source_recall_at_5"] = sum(1 for r in source_found_at.values() if r <= 5) / max(len(expected_sources), 1)
    result["source_recall_at_10"] = sum(1 for r in source_found_at.values() if r <= 10) / max(len(expected_sources), 1)

    # MRR: reciprocal rank of first relevant source
    if source_found_at:
        best_rank = min(source_found_at.values())
        result["mrr"] = 1.0 / best_rank
    else:
        result["mrr"] = 0.0

    # Binary relevance list for NDCG and Precision
    relevance_list = [
        1 if _is_result_relevant(r, expected_sources) else 0
        for r in search_results
    ]

    # NDCG@10: Normalized Discounted Cumulative Gain (binary relevance)
    result["ndcg_at_10"] = _compute_ndcg(relevance_list, k=10)

    # Precision@5 and Precision@10
    result["precision_at_5"] = _compute_precision_at_k(relevance_list, k=5)
    result["precision_at_10"] = _compute_precision_at_k(relevance_list, k=10)

    # Keyword Recall: check if expected keywords appear in combined content
    expected_keywords = query_def.get("expected_keywords", [])
    combined_content = " ".join(r.get("content", "") for r in search_results).lower()
    keywords_found = sum(1 for kw in expected_keywords if kw.lower() in combined_content)
    result["keyword_recall"] = keywords_found / max(len(expected_keywords), 1)

    # Overall relevance score (weighted average)
    result["relevance_score"] = (
        result["source_recall_at_5"] * 0.3 +
        result["source_recall_at_10"] * 0.2 +
        result["keyword_recall"] * 0.3 +
        result["mrr"] * 0.2
    )

    return result


def run_eval(server: str, limit: int = 10) -> dict:
    """Run the full evaluation suite."""
    with open(EVAL_QUERIES_PATH) as f:
        queries = json.load(f)

    print(f"Corvia RAG Retrieval Evaluation")
    print(f"Server: {server}")
    print(f"Queries: {len(queries)}")
    print(f"Top-K: {limit}")
    print("-" * 80)

    results = []
    for q in queries:
        search = mcp_search(server, q["query"], limit)
        if search["error"]:
            print(f"  ERROR {q['id']}: {search['error']}")
            results.append({"id": q["id"], "error": search["error"]})
            continue

        eval_result = evaluate_query(q, search["results"], search["latency_ms"])
        results.append(eval_result)

        status = "PASS" if eval_result["relevance_score"] >= 0.5 else "WEAK" if eval_result["relevance_score"] >= 0.25 else "FAIL"
        print(f"  [{status}] {q['id']:<25} src@5={eval_result['source_recall_at_5']:.0%} "
              f"kw={eval_result['keyword_recall']:.0%} mrr={eval_result['mrr']:.2f} "
              f"ndcg@10={eval_result['ndcg_at_10']:.2f} p@5={eval_result['precision_at_5']:.0%} "
              f"rel={eval_result['relevance_score']:.2f} {eval_result['latency_ms']:.0f}ms")

    # Aggregate metrics
    valid = [r for r in results if "error" not in r]
    n = max(len(valid), 1)
    summary = {
        "total_queries": len(queries),
        "successful": len(valid),
        "errors": len(queries) - len(valid),
        "avg_source_recall_at_5": sum(r["source_recall_at_5"] for r in valid) / n,
        "avg_source_recall_at_10": sum(r["source_recall_at_10"] for r in valid) / n,
        "avg_keyword_recall": sum(r["keyword_recall"] for r in valid) / n,
        "avg_mrr": sum(r["mrr"] for r in valid) / n,
        "avg_ndcg_at_10": sum(r["ndcg_at_10"] for r in valid) / n,
        "avg_precision_at_5": sum(r["precision_at_5"] for r in valid) / n,
        "avg_precision_at_10": sum(r["precision_at_10"] for r in valid) / n,
        "avg_relevance_score": sum(r["relevance_score"] for r in valid) / n,
        "avg_latency_ms": sum(r["latency_ms"] for r in valid) / n,
        "p95_latency_ms": sorted(r["latency_ms"] for r in valid)[int(len(valid) * 0.95)] if valid else 0,
    }

    # By category
    categories = set(r.get("category", "unknown") for r in valid)
    by_category = {}
    for cat in categories:
        cat_results = [r for r in valid if r.get("category") == cat]
        cn = len(cat_results)
        by_category[cat] = {
            "count": cn,
            "avg_relevance": sum(r["relevance_score"] for r in cat_results) / cn,
            "avg_keyword_recall": sum(r["keyword_recall"] for r in cat_results) / cn,
            "avg_ndcg_at_10": sum(r["ndcg_at_10"] for r in cat_results) / cn,
            "avg_precision_at_5": sum(r["precision_at_5"] for r in cat_results) / cn,
            "avg_precision_at_10": sum(r["precision_at_10"] for r in cat_results) / cn,
        }

    # By difficulty
    difficulties = set(r.get("difficulty", "unknown") for r in valid)
    by_difficulty = {}
    for diff in difficulties:
        diff_results = [r for r in valid if r.get("difficulty") == diff]
        dn = len(diff_results)
        by_difficulty[diff] = {
            "count": dn,
            "avg_relevance": sum(r["relevance_score"] for r in diff_results) / dn,
            "avg_ndcg_at_10": sum(r["ndcg_at_10"] for r in diff_results) / dn,
        }

    print("-" * 80)
    print(f"\nSummary:")
    print(f"  Source Recall@5:  {summary['avg_source_recall_at_5']:.1%}")
    print(f"  Source Recall@10: {summary['avg_source_recall_at_10']:.1%}")
    print(f"  Keyword Recall:   {summary['avg_keyword_recall']:.1%}")
    print(f"  MRR:              {summary['avg_mrr']:.3f}")
    print(f"  NDCG@10:          {summary['avg_ndcg_at_10']:.3f}")
    print(f"  Precision@5:      {summary['avg_precision_at_5']:.1%}")
    print(f"  Precision@10:     {summary['avg_precision_at_10']:.1%}")
    print(f"  Relevance Score:  {summary['avg_relevance_score']:.3f}")
    print(f"  Avg Latency:      {summary['avg_latency_ms']:.0f}ms")
    print(f"  P95 Latency:      {summary['p95_latency_ms']:.0f}ms")
    print(f"\nBy Category:")
    for cat, stats in sorted(by_category.items()):
        print(f"  {cat:<15} n={stats['count']} rel={stats['avg_relevance']:.2f} "
              f"kw={stats['avg_keyword_recall']:.0%} ndcg={stats['avg_ndcg_at_10']:.2f} "
              f"p@5={stats['avg_precision_at_5']:.0%}")
    print(f"\nBy Difficulty:")
    for diff, stats in sorted(by_difficulty.items()):
        print(f"  {diff:<10} n={stats['count']} rel={stats['avg_relevance']:.2f} "
              f"ndcg={stats['avg_ndcg_at_10']:.2f}")

    # Save results
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    output = {
        "timestamp": timestamp,
        "server": server,
        "top_k": limit,
        "summary": summary,
        "by_category": by_category,
        "by_difficulty": by_difficulty,
        "details": results,
    }
    output_path = RESULTS_DIR / f"eval-{timestamp}.json"
    with open(output_path, "w") as f:
        json.dump(output, f, indent=2)
    print(f"\nResults saved to: {output_path}")

    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Corvia RAG Retrieval Evaluation")
    parser.add_argument("--server", default="http://localhost:8020", help="Corvia server URL")
    parser.add_argument("--limit", type=int, default=10, help="Top-K results to retrieve")
    args = parser.parse_args()

    run_eval(args.server, args.limit)
