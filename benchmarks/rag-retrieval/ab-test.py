#!/usr/bin/env python3
"""
A/B Test: Vector-only vs Graph-Expanded Retrieval

Runs the eval suite twice — once with graph expansion, once without — and
compares results. Uses corvia's REST API with different query parameters.

Usage:
    python3 benchmarks/rag-retrieval/ab-test.py [--server http://localhost:8020] [--limit 10]
"""

import argparse
import json
import time
import sys
from pathlib import Path
from urllib.request import urlopen, Request
from urllib.error import URLError

EVAL_QUERIES_PATH = Path(__file__).parent / "eval-queries.json"
RESULTS_DIR = Path(__file__).parent / "results"
SERVER = "http://localhost:8020"
LIMIT = 10


def search(query: str, limit: int = 10, expand_graph: bool = True) -> dict:
    """Call corvia context endpoint with configurable graph expansion."""
    payload = json.dumps({
        "query": query,
        "scope_id": "corvia",
        "limit": limit,
        "expand_graph": expand_graph,
    }).encode()

    # Use the RAG context endpoint which respects expand_graph
    req = Request(f"{SERVER}/v1/context", data=payload, headers={"Content-Type": "application/json"})
    start = time.monotonic()
    try:
        with urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
            latency_ms = (time.monotonic() - start) * 1000
    except (URLError, TimeoutError) as e:
        return {"error": str(e), "latency_ms": 0, "results": []}

    # Context endpoint returns sources array
    results = data.get("sources", [])
    return {"results": results, "latency_ms": latency_ms, "error": None}


def evaluate_query(query_def: dict, search_results: list, latency_ms: float) -> dict:
    """Evaluate a single query."""
    result = {
        "id": query_def["id"],
        "latency_ms": round(latency_ms, 1),
        "result_count": len(search_results),
    }

    expected_sources = query_def.get("expected_sources", [])
    source_found_at = {}
    for i, r in enumerate(search_results):
        source = (r.get("source_file", "") or r.get("metadata", {}).get("source_file", "") or "").lower()
        content = (r.get("content", "") or "").lower()
        # Check both source file and content for source matches
        for expected in expected_sources:
            if expected not in source_found_at:
                if expected.lower() in source or expected.lower() in content:
                    source_found_at[expected] = i + 1

    result["source_recall_5"] = sum(1 for r in source_found_at.values() if r <= 5) / max(len(expected_sources), 1)
    result["source_recall_10"] = sum(1 for r in source_found_at.values() if r <= 10) / max(len(expected_sources), 1)

    if source_found_at:
        result["mrr"] = 1.0 / min(source_found_at.values())
    else:
        result["mrr"] = 0.0

    expected_keywords = query_def.get("expected_keywords", [])
    combined = " ".join(r.get("content", "") for r in search_results).lower()
    kw_found = sum(1 for kw in expected_keywords if kw.lower() in combined)
    result["keyword_recall"] = kw_found / max(len(expected_keywords), 1)

    result["relevance"] = (
        result["source_recall_5"] * 0.3 +
        result["source_recall_10"] * 0.2 +
        result["keyword_recall"] * 0.3 +
        result["mrr"] * 0.2
    )
    return result


def run_variant(name: str, expand_graph: bool) -> dict:
    """Run all queries with a specific config."""
    with open(EVAL_QUERIES_PATH) as f:
        queries = json.load(f)

    results = []
    errors = 0
    for q in queries:
        sr = search(q["query"], limit=LIMIT, expand_graph=expand_graph)
        if sr["error"]:
            errors += 1
            continue
        ev = evaluate_query(q, sr["results"], sr["latency_ms"])
        results.append(ev)

    valid = [r for r in results if "error" not in r]
    return {
        "name": name,
        "expand_graph": expand_graph,
        "queries": len(queries),
        "successful": len(valid),
        "errors": errors,
        "avg_recall_5": sum(r["source_recall_5"] for r in valid) / max(len(valid), 1),
        "avg_recall_10": sum(r["source_recall_10"] for r in valid) / max(len(valid), 1),
        "avg_kw_recall": sum(r["keyword_recall"] for r in valid) / max(len(valid), 1),
        "avg_mrr": sum(r["mrr"] for r in valid) / max(len(valid), 1),
        "avg_relevance": sum(r["relevance"] for r in valid) / max(len(valid), 1),
        "avg_latency": sum(r["latency_ms"] for r in valid) / max(len(valid), 1),
        "details": valid,
    }


def main():
    global SERVER, LIMIT

    parser = argparse.ArgumentParser(description="A/B Test: Vector-only vs Graph-Expanded Retrieval")
    parser.add_argument("--server", default=SERVER, help="Server URL (default: %(default)s)")
    parser.add_argument("--limit", type=int, default=LIMIT, help="Results per query (default: %(default)s)")
    args = parser.parse_args()

    SERVER = args.server
    LIMIT = args.limit

    print("=" * 70)
    print("A/B Test: Vector-only vs Graph-Expanded Retrieval")
    print(f"Server: {SERVER}  Limit: {LIMIT}")
    print("=" * 70)

    # Variant A: graph_expand (default)
    print("\n--- Variant A: graph_expand ---")
    a = run_variant("graph_expand", expand_graph=True)
    print(f"  Recall@5={a['avg_recall_5']:.1%}  Recall@10={a['avg_recall_10']:.1%}  "
          f"KW={a['avg_kw_recall']:.1%}  MRR={a['avg_mrr']:.3f}  "
          f"Rel={a['avg_relevance']:.3f}  Lat={a['avg_latency']:.0f}ms  "
          f"({a['successful']}/{a['queries']} ok)")

    # Variant B: vector only
    print("\n--- Variant B: vector ---")
    b = run_variant("vector", expand_graph=False)
    print(f"  Recall@5={b['avg_recall_5']:.1%}  Recall@10={b['avg_recall_10']:.1%}  "
          f"KW={b['avg_kw_recall']:.1%}  MRR={b['avg_mrr']:.3f}  "
          f"Rel={b['avg_relevance']:.3f}  Lat={b['avg_latency']:.0f}ms  "
          f"({b['successful']}/{b['queries']} ok)")

    # Delta
    print("\n--- Delta (graph_expand - vector) ---")
    for metric in ["avg_recall_5", "avg_recall_10", "avg_kw_recall", "avg_mrr", "avg_relevance"]:
        delta = a[metric] - b[metric]
        pct = f"+{delta:.1%}" if delta >= 0 else f"{delta:.1%}"
        winner = "graph" if delta > 0 else "vector" if delta < 0 else "tie"
        print(f"  {metric:<20} graph={a[metric]:.3f}  vector={b[metric]:.3f}  delta={pct}  [{winner}]")

    lat_delta = a["avg_latency"] - b["avg_latency"]
    print(f"  {'avg_latency':<20} graph={a['avg_latency']:.0f}ms  vector={b['avg_latency']:.0f}ms  delta={lat_delta:+.0f}ms")

    # Per-query comparison
    print("\n--- Per-Query Winners ---")
    graph_wins = 0
    vector_wins = 0
    ties = 0
    for qa, qb in zip(a["details"], b["details"]):
        if qa["relevance"] > qb["relevance"] + 0.05:
            graph_wins += 1
            w = "GRAPH"
        elif qb["relevance"] > qa["relevance"] + 0.05:
            vector_wins += 1
            w = "VECTOR"
        else:
            ties += 1
            w = "TIE"
        print(f"  {qa['id']:<25} graph={qa['relevance']:.2f}  vector={qb['relevance']:.2f}  [{w}]")

    print(f"\n  Graph wins: {graph_wins}  Vector wins: {vector_wins}  Ties: {ties}")

    # Save results
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    output = {"timestamp": timestamp, "graph_expand": a, "vector": b}
    path = RESULTS_DIR / f"ab-test-{timestamp}.json"
    with open(path, "w") as f:
        json.dump(output, f, indent=2)
    print(f"\nResults saved to: {path}")


if __name__ == "__main__":
    main()
