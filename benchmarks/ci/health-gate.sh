#!/usr/bin/env bash
# CI Quality Gate — Knowledge Health
#
# Runs the knowledge health eval suite and checks that critical finding types
# stay at zero and total findings stay below a ceiling. Exits 0 on pass, 1 on fail.
#
# Usage:
#   ./benchmarks/ci/health-gate.sh
#   CORVIA_SERVER=http://localhost:8020 ./benchmarks/ci/health-gate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SERVER="${CORVIA_SERVER:-http://localhost:8020}"
SCOPE="${CORVIA_SCOPE:-corvia}"

# ── Thresholds ────────────────────────────────────────────────────────────────
# Critical types: must be zero (data integrity bugs)
THRESHOLD_DEPENDENCY_CYCLE=0
THRESHOLD_BROKEN_CHAIN=0
THRESHOLD_DANGLING_IMPORT=0
# Total findings ceiling (generous; baseline ~3700 orphaned_node)
THRESHOLD_TOTAL=5000

# ── Output ───────────────────────────────────────────────────────────────────
SUMMARY_JSON="${SUMMARY_JSON:-/tmp/health-summary.json}"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

log_pass() { echo -e "  ${GREEN}PASS${NC} $1"; }
log_fail() { echo -e "  ${RED}FAIL${NC} $1"; }
log_info() { echo -e "  ${YELLOW}INFO${NC} $1"; }

# ── Step 1: Health check ─────────────────────────────────────────────────────
echo -e "\n${BOLD}=== Corvia Knowledge Health Gate ===${NC}\n"
echo "Server: $SERVER"
echo "Scope: $SCOPE"
echo ""

echo -e "${BOLD}[1/4] Health check${NC}"
if ! curl -sf --max-time 5 "$SERVER/health" > /dev/null 2>&1; then
    log_fail "Server not reachable at $SERVER/health"
    echo -e "\n${RED}ABORT${NC}: Cannot reach corvia server. Is it running?"
    exit 1
fi
log_pass "Server is healthy"

# ── Step 2: Run health eval ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[2/4] Running health eval${NC}"

EVAL_SCRIPT="$WORKSPACE_ROOT/benchmarks/knowledge-health/eval.py"
if [ ! -f "$EVAL_SCRIPT" ]; then
    log_fail "Health eval script not found at $EVAL_SCRIPT"
    exit 1
fi

# Clean stale results
RESULTS_DIR="$WORKSPACE_ROOT/benchmarks/knowledge-health/results"
rm -f "$RESULTS_DIR"/health-*.json

if ! python3 "$EVAL_SCRIPT" --server "$SERVER" --scope "$SCOPE" --persist; then
    log_fail "Health eval script exited with an error"
    exit 1
fi
log_pass "Health eval completed"

# ── Step 3: Parse results ────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[3/4] Parsing results${NC}"

LATEST=$(ls -t "$RESULTS_DIR"/health-*.json 2>/dev/null | head -1)

if [ -z "$LATEST" ]; then
    log_fail "No health results found in $RESULTS_DIR"
    exit 1
fi
log_info "Results file: $(basename "$LATEST")"

# Extract metrics safely via Python
METRICS_JSON=$(python3 - "$LATEST" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

groups = data.get("groups", {})

json.dump({
    "total_findings": data["total_findings"],
    "check_types_count": data["check_types_count"],
    "dependency_cycle": groups.get("dependency_cycle", {}).get("count", 0),
    "broken_chain": groups.get("broken_chain", {}).get("count", 0),
    "dangling_import": groups.get("dangling_import", {}).get("count", 0),
    "orphaned_node": groups.get("orphaned_node", {}).get("count", 0),
    "stale_entry": groups.get("stale_entry", {}).get("count", 0),
    "groups": {k: v["count"] for k, v in groups.items()},
}, sys.stdout)
PYEOF
)

# Extract all variables in a single Python call
eval "$(echo "$METRICS_JSON" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for k in ['total_findings', 'dependency_cycle', 'broken_chain', 'dangling_import', 'check_types_count']:
    # Values are always non-negative integers from our own JSON — safe to eval
    print(f'{k}={d[k]}')
")"

echo "  Total findings: $total_findings"
echo "  Check types: $check_types_count"
echo ""

# ── Step 4: Check thresholds ─────────────────────────────────────────────────
echo -e "${BOLD}[4/4] Threshold checks${NC}"

FAILURES=0

check_threshold() {
    local name="$1"
    local value="$2"
    local threshold="$3"

    if [ "$value" -le "$threshold" ] 2>/dev/null; then
        log_pass "$name: $value <= $threshold"
    else
        log_fail "$name: $value > $threshold"
        FAILURES=$((FAILURES + 1))
    fi
}

check_threshold "dependency_cycle"  "$dependency_cycle"  "$THRESHOLD_DEPENDENCY_CYCLE"
check_threshold "broken_chain"      "$broken_chain"      "$THRESHOLD_BROKEN_CHAIN"
check_threshold "dangling_import"   "$dangling_import"   "$THRESHOLD_DANGLING_IMPORT"
check_threshold "Total findings"    "$total_findings"    "$THRESHOLD_TOTAL"

# ── Write JSON summary ────────────────────────────────────────────────────────
echo "$METRICS_JSON" | python3 - "$SUMMARY_JSON" "$LATEST" \
    "$FAILURES" "$dependency_cycle" "$THRESHOLD_DEPENDENCY_CYCLE" \
    "$broken_chain" "$THRESHOLD_BROKEN_CHAIN" \
    "$dangling_import" "$THRESHOLD_DANGLING_IMPORT" \
    "$total_findings" "$THRESHOLD_TOTAL" <<'PYEOF'
import json, sys, os

metrics = json.load(sys.stdin)
failures = int(sys.argv[3])

summary = {
    "passed": failures == 0,
    "failures": failures,
    "results_file": os.path.basename(sys.argv[2]),
    "checks": {
        "dependency_cycle": {"value": int(sys.argv[4]),  "threshold": int(sys.argv[5])},
        "broken_chain":     {"value": int(sys.argv[6]),  "threshold": int(sys.argv[7])},
        "dangling_import":  {"value": int(sys.argv[8]),  "threshold": int(sys.argv[9])},
        "total_findings":   {"value": int(sys.argv[10]), "threshold": int(sys.argv[11])},
    },
    "all_types": metrics.get("groups", {}),
}

with open(sys.argv[1], "w") as f:
    json.dump(summary, f, indent=2)
PYEOF
log_info "Summary written to $SUMMARY_JSON"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}PASSED${NC} — All health gates met."
    exit 0
else
    echo -e "${RED}${BOLD}FAILED${NC} — $FAILURES threshold(s) breached."
    echo -e "  Run locally: ${BOLD}./benchmarks/ci/health-gate.sh${NC}"
    echo -e "  Details: ${BOLD}$RESULTS_DIR/${NC}"
    exit 1
fi
