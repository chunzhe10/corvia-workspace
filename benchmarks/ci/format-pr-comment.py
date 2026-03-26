#!/usr/bin/env python3
"""
Format eval-gate results as a markdown PR comment.

Reads the JSON summary produced by eval-gate.sh and outputs a markdown table
with metrics, thresholds, baseline deltas, and pass/fail status.

Usage:
    python3 benchmarks/ci/format-pr-comment.py [--summary /tmp/eval-summary.json]
"""

import argparse
import json
import sys
from pathlib import Path

DEFAULT_SUMMARY = Path("/tmp/eval-summary.json")

# HTML marker for idempotent comment replacement
COMMENT_MARKER = "<!-- eval-gate-comment -->"


def delta_str(value: float, baseline: float) -> str:
    """Format delta vs baseline as +X.XXX or -X.XXX."""
    d = value - baseline
    sign = "+" if d >= 0 else ""
    return f"{sign}{d:.3f}"


def format_comment(summary: dict) -> str:
    """Format the eval summary as a markdown PR comment."""
    passed = summary["passed"]
    metrics = summary["metrics"]
    queries = summary["queries"]
    latency = summary["avg_latency_ms"]

    title = "\u2705 RAG Quality Gate \u2014 PASSED" if passed else "\u274c RAG Quality Gate \u2014 FAILED"

    lines = [
        COMMENT_MARKER,
        f"## {title}",
        "",
        "| Metric | Value | Threshold | Baseline (Mar 19) | vs Baseline | Status |",
        "|--------|------:|----------:|-------------------:|------------:|--------|",
    ]

    display_names = {
        "mrr": "MRR",
        "source_recall_5": "Source Recall@5",
        "keyword_recall": "Keyword Recall",
    }

    for key, m in metrics.items():
        name = display_names.get(key, key)
        passed_metric = m["value"] >= m["threshold"]
        icon = "\u2705" if passed_metric else "\u274c"
        delta = delta_str(m["value"], m["baseline"])
        lines.append(
            f"| {name} | {m['value']:.3f} | {m['threshold']:.2f} | {m['baseline']:.3f} | {delta} | {icon} |"
        )

    # Timeouts row (lower is better)
    max_timeouts = queries.get("max_timeouts", 3)
    timeout_ok = queries["timeouts"] <= max_timeouts
    timeout_icon = "\u2705" if timeout_ok else "\u274c"
    lines.append(
        f"| Query Timeouts | {queries['timeouts']} | \u2264{max_timeouts} | \u2014 | \u2014 | {timeout_icon} |"
    )

    # Query stats
    error_warning = " \u26a0\ufe0f" if queries["errors"] > 0 else ""
    lines.extend([
        "",
        f"**Queries**: {queries['total']} total, {queries['successful']} successful, "
        f"{queries['errors']} errors{error_warning}, {queries['timeouts']} timeouts",
        f"**Avg latency**: {latency:.0f}ms",
    ])

    # Failure guidance
    if not passed:
        lines.extend([
            "",
            "### Next steps",
            "1. Run locally: `./benchmarks/ci/eval-gate.sh`",
            "2. Check per-query details in `benchmarks/rag-retrieval/results/`",
            "3. Compare against eval queries in `benchmarks/rag-retrieval/eval-queries.json`",
        ])

    lines.extend([
        "",
        "<details>",
        f"<summary>Results file: <code>{summary['results_file']}</code></summary>",
        "",
        "```bash",
        "# Run locally",
        "./benchmarks/ci/eval-gate.sh",
        "",
        "# Override server URL",
        "CORVIA_SERVER=http://localhost:8020 ./benchmarks/ci/eval-gate.sh",
        "```",
        "</details>",
    ])

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Format eval-gate results as PR comment")
    parser.add_argument("--summary", type=Path, default=DEFAULT_SUMMARY, help="Path to eval-summary.json")
    parser.add_argument("--output", type=Path, default=None, help="Write to file instead of stdout")
    args = parser.parse_args()

    if not args.summary.exists():
        print(f"Error: summary file not found: {args.summary}", file=sys.stderr)
        sys.exit(1)

    with open(args.summary) as f:
        summary = json.load(f)

    comment = format_comment(summary)

    if args.output:
        args.output.write_text(comment, encoding="utf-8")
    else:
        print(comment)


if __name__ == "__main__":
    main()
