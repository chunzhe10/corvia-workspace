#!/usr/bin/env python3
"""
Corvia Knowledge Health Evaluation — Dogfooding Edition

Calls the /v1/reason endpoint to run deterministic health checks on the
knowledge base, then tracks findings over time to detect regressions.

Metrics:
- Total finding count (delta vs previous run)
- Count per check_type (delta vs previous)
- New/removed check types since last run

Usage:
    python3 benchmarks/knowledge-health/eval.py [--server http://localhost:8020] [--scope corvia]
"""

import json
import sys
import argparse
import glob
from datetime import datetime, timezone
from pathlib import Path
from collections import Counter
from urllib.request import urlopen, Request
from urllib.error import URLError

RESULTS_DIR = Path(__file__).parent / "results"


def call_reason(server: str, scope_id: str) -> dict:
    """Call POST /v1/reason and return parsed JSON."""
    payload = json.dumps({"scope_id": scope_id}).encode()
    req = Request(
        f"{server}/v1/reason",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urlopen(req, timeout=60) as resp:
            return json.loads(resp.read())
    except (URLError, TimeoutError) as e:
        print(f"ERROR: Could not reach {server}/v1/reason — {e}", file=sys.stderr)
        sys.exit(1)


def group_findings(findings: list) -> dict:
    """Group findings by check_type and return counts + samples."""
    counter = Counter(f["check_type"] for f in findings)
    groups = {}
    for check_type, count in counter.most_common():
        sample = next(f for f in findings if f["check_type"] == check_type)
        groups[check_type] = {
            "count": count,
            "sample_rationale": sample["rationale"],
            "confidence": sample.get("confidence"),
        }
    return groups


def load_previous_result() -> dict | None:
    """Load the most recent result file, if any."""
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    files = sorted(glob.glob(str(RESULTS_DIR / "health-*.json")))
    if not files:
        return None
    with open(files[-1]) as f:
        return json.load(f)


def compute_delta(current_groups: dict, previous: dict | None) -> dict:
    """Compute delta between current and previous run."""
    if previous is None:
        return {"first_run": True}

    prev_groups = previous.get("groups", {})
    delta = {}
    all_types = set(list(current_groups.keys()) + list(prev_groups.keys()))

    for check_type in sorted(all_types):
        curr_count = current_groups.get(check_type, {}).get("count", 0)
        prev_count = prev_groups.get(check_type, {}).get("count", 0)
        diff = curr_count - prev_count
        if diff != 0 or check_type in current_groups:
            delta[check_type] = {
                "current": curr_count,
                "previous": prev_count,
                "delta": diff,
            }

    new_types = set(current_groups.keys()) - set(prev_groups.keys())
    removed_types = set(prev_groups.keys()) - set(current_groups.keys())

    return {
        "first_run": False,
        "types": delta,
        "new_types": sorted(new_types) if new_types else [],
        "removed_types": sorted(removed_types) if removed_types else [],
        "previous_file": previous.get("timestamp", "unknown"),
    }


def save_result(result: dict) -> Path:
    """Save result to timestamped JSON file."""
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    ts = result["timestamp"].replace(":", "").replace("-", "")
    path = RESULTS_DIR / f"health-{ts}.json"
    with open(path, "w") as f:
        json.dump(result, f, indent=2)
    return path


def print_report(result: dict, delta: dict):
    """Print human-readable report to stdout."""
    print("=" * 60)
    print("  Corvia Knowledge Health Report")
    print(f"  Scope: {result['scope_id']}  |  {result['timestamp']}")
    print("=" * 60)
    print()
    print(f"  Total findings: {result['total_findings']}")
    print()

    # Per-type breakdown
    print("  Findings by check_type:")
    print("  " + "-" * 44)
    for check_type, info in sorted(result["groups"].items(), key=lambda x: -x[1]["count"]):
        count = info["count"]
        delta_str = ""
        if not delta.get("first_run") and check_type in delta.get("types", {}):
            d = delta["types"][check_type]["delta"]
            if d > 0:
                delta_str = f"  (+{d})"
            elif d < 0:
                delta_str = f"  ({d})"
        print(f"    {check_type:30s} {count:>5d}{delta_str}")
    print()

    # Delta summary
    if delta.get("first_run"):
        print("  First run — no previous data to compare.")
    else:
        prev_total = sum(d["previous"] for d in delta.get("types", {}).values())
        curr_total = result["total_findings"]
        total_delta = curr_total - prev_total
        sign = "+" if total_delta > 0 else ""
        print(f"  vs previous run ({delta.get('previous_file', 'unknown')}):")
        print(f"    Total delta: {sign}{total_delta}")

        if delta.get("new_types"):
            print(f"    NEW check types: {', '.join(delta['new_types'])}")
        if delta.get("removed_types"):
            print(f"    RESOLVED check types: {', '.join(delta['removed_types'])}")

    print()
    print("=" * 60)


def main():
    parser = argparse.ArgumentParser(description="Corvia Knowledge Health Evaluation")
    parser.add_argument("--server", default="http://localhost:8020", help="corvia server URL")
    parser.add_argument("--scope", default="corvia", help="Scope ID to check")
    args = parser.parse_args()

    # Call reason endpoint
    print(f"Calling {args.server}/v1/reason (scope: {args.scope})...")
    data = call_reason(args.server, args.scope)

    total = data.get("count", len(data.get("findings", [])))
    findings = data.get("findings", [])
    groups = group_findings(findings)

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    result = {
        "timestamp": timestamp,
        "scope_id": args.scope,
        "total_findings": total,
        "check_types_count": len(groups),
        "groups": groups,
    }

    # Compare to previous
    previous = load_previous_result()
    delta = compute_delta(groups, previous)
    result["delta"] = delta

    # Save
    path = save_result(result)
    print(f"Saved: {path}")
    print()

    # Report
    print_report(result, delta)

    # Exit code: 0 if no new types appeared, 1 if regression detected
    if delta.get("new_types"):
        print("WARNING: New check types detected — review above.")
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
