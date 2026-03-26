#!/usr/bin/env python3
"""
Format health-gate results as a markdown PR comment.

Reads the JSON summary produced by health-gate.sh and outputs a markdown table
with per-check-type counts, thresholds, and pass/fail status.

Usage:
    python3 benchmarks/ci/format-health-comment.py [--summary /tmp/health-summary.json]
"""

import argparse
import json
import sys
from pathlib import Path

DEFAULT_SUMMARY = Path("/tmp/health-summary.json")

COMMENT_MARKER = "<!-- health-gate-comment -->"


def format_comment(summary: dict) -> str:
    """Format the health summary as a markdown PR comment."""
    passed = summary["passed"]
    checks = summary["checks"]
    all_types = summary.get("all_types", {})

    title = "\u2705 Knowledge Health Gate \u2014 PASSED" if passed else "\u274c Knowledge Health Gate \u2014 FAILED"

    lines = [
        COMMENT_MARKER,
        f"## {title}",
        "",
        "### Critical Checks",
        "",
        "| Check Type | Count | Threshold | Status |",
        "|------------|------:|----------:|--------|",
    ]

    for key, c in checks.items():
        icon = "\u2705" if c["value"] <= c["threshold"] else "\u274c"
        display = key.replace("_", " ").title()
        lines.append(f"| {display} | {c['value']} | \u2264{c['threshold']} | {icon} |")

    if not passed:
        lines.extend([
            "",
            "### Next steps",
            "1. Run locally: `./benchmarks/ci/health-gate.sh`",
            "2. Check findings: `python3 benchmarks/knowledge-health/eval.py`",
            "3. Investigate critical types (dependency_cycle, broken_chain, dangling_import) — these indicate data integrity issues",
        ])

    # All finding types in collapsible details
    detail_lines = []
    if all_types:
        detail_lines.extend([
            "",
            "**All finding types:**",
            "",
            "| Check Type | Count |",
            "|------------|------:|",
        ])
        for ct, count in sorted(all_types.items(), key=lambda x: -x[1]):
            detail_lines.append(f"| {ct} | {count} |")

    lines.extend([
        "",
        "<details>",
        f"<summary>Results file: <code>{summary['results_file']}</code></summary>",
        *detail_lines,
        "",
        "```bash",
        "# Run locally",
        "./benchmarks/ci/health-gate.sh",
        "",
        "# Override server URL",
        "CORVIA_SERVER=http://localhost:8020 ./benchmarks/ci/health-gate.sh",
        "```",
        "</details>",
    ])

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Format health-gate results as PR comment")
    parser.add_argument("--summary", type=Path, default=DEFAULT_SUMMARY, help="Path to health-summary.json")
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
