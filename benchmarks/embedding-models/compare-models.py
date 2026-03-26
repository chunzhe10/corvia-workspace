#!/usr/bin/env python3
"""
Compare two embedding model eval results side-by-side.

Reads two eval result JSON files (from benchmarks/rag-retrieval/eval.py) and
produces a comparison report with per-metric, per-query, and per-category
breakdowns.

Usage:
    python3 compare-models.py results/model-a.json results/model-b.json \
        --model-a nomic-embed-text-v1.5 --model-b all-MiniLM-L6-v2

    # With dogfooding
    python3 compare-models.py a.json b.json --persist --server http://localhost:8020
"""

import argparse
import json
import sys
import time
from pathlib import Path
from urllib.request import urlopen, Request
from urllib.error import URLError

RESULTS_DIR = Path(__file__).parent / "results"


def load_eval(path: str) -> dict:
    """Load an eval result JSON file."""
    with open(path) as f:
        return json.load(f)


def delta_str(a: float, b: float) -> str:
    """Format delta as +X.XXX or -X.XXX."""
    d = a - b
    return f"{'+' if d >= 0 else ''}{d:.3f}"


def compare(a: dict, b: dict, name_a: str, name_b: str) -> dict:
    """Compare two eval results and return comparison dict."""
    sa, sb = a["summary"], b["summary"]

    metrics = [
        ("MRR", "avg_mrr"),
        ("Source Recall@5", "avg_source_recall_at_5"),
        ("Source Recall@10", "avg_source_recall_at_10"),
        ("Keyword Recall", "avg_keyword_recall"),
        ("NDCG@10", "avg_ndcg_at_10"),
        ("Precision@5", "avg_precision_at_5"),
        ("Precision@10", "avg_precision_at_10"),
        ("Avg Latency (ms)", "avg_latency_ms"),
        ("P95 Latency (ms)", "p95_latency_ms"),
    ]

    comparison = {
        "model_a": name_a,
        "model_b": name_b,
        "metrics": {},
        "per_query": [],
        "by_category": {},
    }

    # Overall metrics
    print(f"\n{'='*70}")
    print(f"  Embedding Model Comparison: {name_a} vs {name_b}")
    print(f"{'='*70}\n")
    print(f"  {'Metric':<22} {name_a:>12} {name_b:>12} {'Delta':>10} {'Winner':>8}")
    print(f"  {'-'*64}")

    for display, key in metrics:
        va = sa.get(key, 0)
        vb = sb.get(key, 0)
        d = va - vb
        # For latency, lower is better
        if "latency" in key.lower():
            winner = name_a if d < 0 else name_b if d > 0 else "tie"
        else:
            winner = name_a if d > 0 else name_b if d < 0 else "tie"

        fmt = ".0f" if "latency" in key.lower() else ".3f"
        print(f"  {display:<22} {va:>12{fmt}} {vb:>12{fmt}} {d:>+10{fmt}} {winner:>8}")

        comparison["metrics"][key] = {
            "model_a": va, "model_b": vb, "delta": d, "winner": winner,
        }

    # Per-query comparison
    da = {d["id"]: d for d in a.get("details", []) if "error" not in d}
    db = {d["id"]: d for d in b.get("details", []) if "error" not in d}
    common_ids = sorted(set(da.keys()) & set(db.keys()))

    a_wins, b_wins, ties = 0, 0, 0
    print(f"\n  Per-Query Winners (relevance, threshold=5%)")
    print(f"  {'-'*55}")
    for qid in common_ids:
        ra = da[qid].get("relevance_score", 0)
        rb = db[qid].get("relevance_score", 0)
        if ra > rb + 0.05:
            winner = name_a
            a_wins += 1
        elif rb > ra + 0.05:
            winner = name_b
            b_wins += 1
        else:
            winner = "tie"
            ties += 1
        print(f"  {qid:<25} {name_a}={ra:.2f}  {name_b}={rb:.2f}  [{winner}]")
        comparison["per_query"].append({"id": qid, "a": ra, "b": rb, "winner": winner})

    print(f"\n  {name_a} wins: {a_wins}  {name_b} wins: {b_wins}  Ties: {ties}")

    # By category
    cats_a = a.get("by_category", {})
    cats_b = b.get("by_category", {})
    all_cats = sorted(set(list(cats_a.keys()) + list(cats_b.keys())))
    if all_cats:
        print(f"\n  By Category")
        print(f"  {'-'*55}")
        for cat in all_cats:
            rel_a = cats_a.get(cat, {}).get("avg_relevance", 0)
            rel_b = cats_b.get(cat, {}).get("avg_relevance", 0)
            winner = name_a if rel_a > rel_b else name_b if rel_b > rel_a else "tie"
            print(f"  {cat:<15} {name_a}={rel_a:.2f}  {name_b}={rel_b:.2f}  [{winner}]")
            comparison["by_category"][cat] = {"a": rel_a, "b": rel_b, "winner": winner}

    overall_winner = name_a if a_wins > b_wins else name_b if b_wins > a_wins else "tie"
    comparison["summary"] = {
        "a_wins": a_wins, "b_wins": b_wins, "ties": ties,
        "overall_winner": overall_winner,
    }

    print(f"\n  {'='*40}")
    print(f"  WINNER: {overall_winner.upper()}" if overall_winner != "tie" else "  RESULT: TIE")
    print(f"  {'='*40}")

    return comparison


def persist_to_corvia(server: str, comparison: dict):
    """Persist comparison to corvia as a knowledge entry."""
    m = comparison["metrics"]
    name_a, name_b = comparison["model_a"], comparison["model_b"]
    s = comparison["summary"]

    lines = [
        f"# Embedding Model Comparison: {name_a} vs {name_b}",
        "",
        f"**Winner**: {s['overall_winner']} ({s['a_wins']} wins vs {s['b_wins']} wins, {s['ties']} ties)",
        "",
        "| Metric | " + name_a + " | " + name_b + " | Delta |",
        "|--------|------:|------:|------:|",
    ]
    for key, v in m.items():
        fmt = ".0f" if "latency" in key else ".3f"
        lines.append(f"| {key} | {v['model_a']:{fmt}} | {v['model_b']:{fmt}} | {v['delta']:+{fmt}} |")

    content = "\n".join(lines)
    payload = json.dumps({
        "content": content,
        "scope_id": "corvia",
        "source_version": f"model-comparison-{time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())}",
        "metadata": {
            "content_role": "finding",
            "source_origin": "workspace",
            "source_file": "benchmarks/embedding-models/compare-models.py",
        },
    }).encode()
    req = Request(f"{server}/v1/memories/write", data=payload, headers={"Content-Type": "application/json"})
    try:
        with urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
            print(f"\n  Persisted to corvia: entry {data.get('id', 'unknown')}")
    except (URLError, TimeoutError) as e:
        print(f"\n  WARNING: Failed to persist to corvia: {e}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description="Compare embedding model eval results")
    parser.add_argument("result_a", help="Path to Model A eval results JSON")
    parser.add_argument("result_b", help="Path to Model B eval results JSON")
    parser.add_argument("--model-a", default="model-a", help="Name for Model A")
    parser.add_argument("--model-b", default="model-b", help="Name for Model B")
    parser.add_argument("--persist", action="store_true", help="Persist to corvia (dogfooding)")
    parser.add_argument("--server", default="http://localhost:8020", help="Server URL for --persist")
    args = parser.parse_args()

    a = load_eval(args.result_a)
    b = load_eval(args.result_b)

    comparison = compare(a, b, args.model_a, args.model_b)

    # Save comparison JSON
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    timestamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    out_path = RESULTS_DIR / f"model-comparison-{timestamp}.json"
    with open(out_path, "w") as f:
        json.dump(comparison, f, indent=2)
    print(f"\n  Comparison saved to: {out_path}")

    if args.persist:
        persist_to_corvia(args.server, comparison)


if __name__ == "__main__":
    main()
