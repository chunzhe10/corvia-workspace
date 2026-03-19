#!/usr/bin/env python3
"""
Corvia RAG Retrieval Evaluation Suite — Dogfooding Edition

Uses corvia's own MCP API to evaluate retrieval quality against known-answer
queries derived from corvia's own documentation and design decisions.

Metrics:
- Source Recall@K: Does the expected source file appear in top-K results?
- Keyword Recall: Do expected keywords appear in retrieved content?
- MRR (Mean Reciprocal Rank): Average 1/rank of first relevant result
- Latency: End-to-end retrieval time per query

Usage:
    python3 benchmarks/rag-retrieval/eval.py [--server http://localhost:8020] [--limit 10]
"""

import json
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
              f"rel={eval_result['relevance_score']:.2f} {eval_result['latency_ms']:.0f}ms")

    # Aggregate metrics
    valid = [r for r in results if "error" not in r]
    summary = {
        "total_queries": len(queries),
        "successful": len(valid),
        "errors": len(queries) - len(valid),
        "avg_source_recall_at_5": sum(r["source_recall_at_5"] for r in valid) / max(len(valid), 1),
        "avg_source_recall_at_10": sum(r["source_recall_at_10"] for r in valid) / max(len(valid), 1),
        "avg_keyword_recall": sum(r["keyword_recall"] for r in valid) / max(len(valid), 1),
        "avg_mrr": sum(r["mrr"] for r in valid) / max(len(valid), 1),
        "avg_relevance_score": sum(r["relevance_score"] for r in valid) / max(len(valid), 1),
        "avg_latency_ms": sum(r["latency_ms"] for r in valid) / max(len(valid), 1),
        "p95_latency_ms": sorted(r["latency_ms"] for r in valid)[int(len(valid) * 0.95)] if valid else 0,
    }

    # By category
    categories = set(r.get("category", "unknown") for r in valid)
    by_category = {}
    for cat in categories:
        cat_results = [r for r in valid if r.get("category") == cat]
        by_category[cat] = {
            "count": len(cat_results),
            "avg_relevance": sum(r["relevance_score"] for r in cat_results) / len(cat_results),
            "avg_keyword_recall": sum(r["keyword_recall"] for r in cat_results) / len(cat_results),
        }

    # By difficulty
    difficulties = set(r.get("difficulty", "unknown") for r in valid)
    by_difficulty = {}
    for diff in difficulties:
        diff_results = [r for r in valid if r.get("difficulty") == diff]
        by_difficulty[diff] = {
            "count": len(diff_results),
            "avg_relevance": sum(r["relevance_score"] for r in diff_results) / len(diff_results),
        }

    print("-" * 80)
    print(f"\nSummary:")
    print(f"  Source Recall@5:  {summary['avg_source_recall_at_5']:.1%}")
    print(f"  Source Recall@10: {summary['avg_source_recall_at_10']:.1%}")
    print(f"  Keyword Recall:   {summary['avg_keyword_recall']:.1%}")
    print(f"  MRR:              {summary['avg_mrr']:.3f}")
    print(f"  Relevance Score:  {summary['avg_relevance_score']:.3f}")
    print(f"  Avg Latency:      {summary['avg_latency_ms']:.0f}ms")
    print(f"  P95 Latency:      {summary['p95_latency_ms']:.0f}ms")
    print(f"\nBy Category:")
    for cat, stats in sorted(by_category.items()):
        print(f"  {cat:<15} n={stats['count']} rel={stats['avg_relevance']:.2f} kw={stats['avg_keyword_recall']:.0%}")
    print(f"\nBy Difficulty:")
    for diff, stats in sorted(by_difficulty.items()):
        print(f"  {diff:<10} n={stats['count']} rel={stats['avg_relevance']:.2f}")

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
