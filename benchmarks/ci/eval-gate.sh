#!/usr/bin/env bash
# CI Quality Gate — RAG Retrieval Evaluation
#
# Runs the RAG retrieval eval suite against a live corvia server and checks
# that key metrics meet minimum thresholds. Exits 0 on pass, 1 on fail.
#
# Usage:
#   ./benchmarks/ci/eval-gate.sh
#   CORVIA_SERVER=http://localhost:8020 ./benchmarks/ci/eval-gate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SERVER="${CORVIA_SERVER:-http://localhost:8020}"
EVAL_LIMIT="${EVAL_LIMIT:-10}"

# ── Thresholds ────────────────────────────────────────────────────────────────
THRESHOLD_MRR="0.4"
THRESHOLD_SOURCE_RECALL="0.30"
THRESHOLD_KEYWORD_RECALL="0.50"
MAX_TIMEOUTS=3

# ── Baselines (from Phase 1, 2026-03-19) ────────────────────────────────────
BASELINE_MRR="0.544"
BASELINE_SOURCE_RECALL="0.375"
BASELINE_KEYWORD_RECALL="0.65"

# ── Output ───────────────────────────────────────────────────────────────────
# JSON summary for CI consumption (PR comments, etc.)
SUMMARY_JSON="${SUMMARY_JSON:-/tmp/eval-summary.json}"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_pass() { echo -e "  ${GREEN}PASS${NC} $1"; }
log_fail() { echo -e "  ${RED}FAIL${NC} $1"; }
log_info() { echo -e "  ${YELLOW}INFO${NC} $1"; }

# ── Step 1: Health check ─────────────────────────────────────────────────────
echo -e "\n${BOLD}=== Corvia CI Quality Gate ===${NC}\n"
echo "Server: $SERVER"
echo "Eval limit: $EVAL_LIMIT"
echo ""

echo -e "${BOLD}[1/4] Health check${NC}"
if ! curl -sf --max-time 5 "$SERVER/health" > /dev/null 2>&1; then
    log_fail "Server not reachable at $SERVER/health"
    echo -e "\n${RED}ABORT${NC}: Cannot reach corvia server. Is it running?"
    exit 1
fi
log_pass "Server is healthy"

# ── Step 2: Run eval suite ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[2/4] Running eval suite${NC}"

EVAL_SCRIPT="$WORKSPACE_ROOT/benchmarks/rag-retrieval/eval.py"
if [ ! -f "$EVAL_SCRIPT" ]; then
    log_fail "Eval script not found at $EVAL_SCRIPT"
    exit 1
fi

# Clean stale results to ensure we pick up this run's output
RESULTS_DIR="$WORKSPACE_ROOT/benchmarks/rag-retrieval/results"
rm -f "$RESULTS_DIR"/eval-*.json

if ! python3 "$EVAL_SCRIPT" --server "$SERVER" --limit "$EVAL_LIMIT"; then
    log_fail "Eval script exited with an error"
    exit 1
fi
log_pass "Eval suite completed"

# ── Step 3: Parse latest results ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}[3/4] Parsing results${NC}"

LATEST=$(ls -t "$RESULTS_DIR"/eval-*.json 2>/dev/null | head -1)

if [ -z "$LATEST" ]; then
    log_fail "No eval results found in $RESULTS_DIR"
    exit 1
fi
log_info "Results file: $(basename "$LATEST")"

# Extract metrics via Python, passing file path as argument (not interpolated)
METRICS_JSON=$(python3 - "$LATEST" <<'PYEOF'
import json, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

s = data["summary"]

# Count timeouts: check for "timed out" substring in error strings
timeouts = sum(1 for d in data.get("details", []) if "timed out" in (d.get("error") or "").lower())

json.dump({
    "mrr": round(s["avg_mrr"], 4),
    "source_recall": round(s["avg_source_recall_at_5"], 4),
    "keyword_recall": round(s["avg_keyword_recall"], 4),
    "timeouts": timeouts,
    "total_queries": s["total_queries"],
    "successful": s["successful"],
    "errors": s["errors"],
    "avg_latency_ms": round(s["avg_latency_ms"], 1),
}, sys.stdout)
PYEOF
)

# Parse JSON into shell variables safely using Python
mrr=$(echo "$METRICS_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['mrr'])")
source_recall=$(echo "$METRICS_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['source_recall'])")
keyword_recall=$(echo "$METRICS_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['keyword_recall'])")
timeouts=$(echo "$METRICS_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['timeouts'])")
total_queries=$(echo "$METRICS_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['total_queries'])")
successful=$(echo "$METRICS_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['successful'])")
errors=$(echo "$METRICS_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['errors'])")
avg_latency_ms=$(echo "$METRICS_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['avg_latency_ms'])")

echo "  Queries: $total_queries total, $successful successful, $errors errors"
echo "  Latency: ${avg_latency_ms}ms avg"
echo ""

# ── Step 4: Check thresholds ─────────────────────────────────────────────────
echo -e "${BOLD}[4/4] Threshold checks${NC}"

FAILURES=0

check_threshold() {
    local name="$1"
    local value="$2"
    local threshold="$3"
    local compare="${4:-gte}"  # gte or lte

    if [ "$compare" = "gte" ]; then
        if python3 -c "import sys; sys.exit(0 if float('$value') >= float('$threshold') else 1)"; then
            log_pass "$name: $value >= $threshold"
        else
            log_fail "$name: $value < $threshold"
            FAILURES=$((FAILURES + 1))
        fi
    else
        if python3 -c "import sys; sys.exit(0 if float('$value') <= float('$threshold') else 1)"; then
            log_pass "$name: $value <= $threshold"
        else
            log_fail "$name: $value > $threshold"
            FAILURES=$((FAILURES + 1))
        fi
    fi
}

check_threshold "MRR"              "$mrr"             "$THRESHOLD_MRR"
check_threshold "Source Recall@5"  "$source_recall"   "$THRESHOLD_SOURCE_RECALL"
check_threshold "Keyword Recall"   "$keyword_recall"  "$THRESHOLD_KEYWORD_RECALL"
check_threshold "Query Timeouts"   "$timeouts"        "$MAX_TIMEOUTS" "lte"

# ── Write JSON summary ────────────────────────────────────────────────────────
python3 - "$SUMMARY_JSON" "$LATEST" <<PYEOF
import json, sys, os

summary = {
    "passed": $FAILURES == 0,
    "failures": $FAILURES,
    "results_file": os.path.basename(sys.argv[2]),
    "metrics": {
        "mrr":             {"value": $mrr,             "threshold": $THRESHOLD_MRR,             "baseline": $BASELINE_MRR},
        "source_recall_5": {"value": $source_recall,   "threshold": $THRESHOLD_SOURCE_RECALL,   "baseline": $BASELINE_SOURCE_RECALL},
        "keyword_recall":  {"value": $keyword_recall,  "threshold": $THRESHOLD_KEYWORD_RECALL,  "baseline": $BASELINE_KEYWORD_RECALL},
    },
    "queries": {
        "total": $total_queries,
        "successful": $successful,
        "errors": $errors,
        "timeouts": $timeouts,
        "max_timeouts": $MAX_TIMEOUTS,
    },
    "avg_latency_ms": $avg_latency_ms,
}

with open(sys.argv[1], "w") as f:
    json.dump(summary, f, indent=2)
PYEOF
log_info "Summary written to $SUMMARY_JSON"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}PASSED${NC} — All quality gates met."
    exit 0
else
    echo -e "${RED}${BOLD}FAILED${NC} — $FAILURES threshold(s) breached."
    echo -e "  Run locally: ${BOLD}./benchmarks/ci/eval-gate.sh${NC}"
    echo -e "  Per-query details: ${BOLD}$RESULTS_DIR/${NC}"
    echo -e "  Thresholds: ${BOLD}benchmarks/ci/eval-gate.sh${NC} (lines 20-23)"
    exit 1
fi
