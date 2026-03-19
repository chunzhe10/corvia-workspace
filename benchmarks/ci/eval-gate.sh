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
THRESHOLD_SOURCE_RECALL="0.25"
THRESHOLD_KEYWORD_RECALL="0.50"
MAX_TIMEOUTS=3

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

pass() { echo -e "  ${GREEN}PASS${NC} $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; }
info() { echo -e "  ${YELLOW}INFO${NC} $1"; }

# ── Step 1: Health check ─────────────────────────────────────────────────────
echo -e "\n${BOLD}=== Corvia CI Quality Gate ===${NC}\n"
echo "Server: $SERVER"
echo "Eval limit: $EVAL_LIMIT"
echo ""

echo -e "${BOLD}[1/4] Health check${NC}"
if ! curl -sf --max-time 5 "$SERVER/health" > /dev/null 2>&1; then
    fail "Server not reachable at $SERVER/health"
    echo -e "\n${RED}ABORT${NC}: Cannot reach corvia server. Is it running?"
    exit 1
fi
pass "Server is healthy"

# ── Step 2: Run eval suite ───────────────────────────────────────────────────
echo ""
echo -e "${BOLD}[2/4] Running eval suite${NC}"

EVAL_SCRIPT="$WORKSPACE_ROOT/benchmarks/rag-retrieval/eval.py"
if [ ! -f "$EVAL_SCRIPT" ]; then
    fail "Eval script not found at $EVAL_SCRIPT"
    exit 1
fi

if ! python3 "$EVAL_SCRIPT" --server "$SERVER" --limit "$EVAL_LIMIT"; then
    fail "Eval script exited with an error"
    exit 1
fi
pass "Eval suite completed"

# ── Step 3: Parse latest results ─────────────────────────────────────────────
echo ""
echo -e "${BOLD}[3/4] Parsing results${NC}"

RESULTS_DIR="$WORKSPACE_ROOT/benchmarks/rag-retrieval/results"
LATEST=$(ls -t "$RESULTS_DIR"/eval-*.json 2>/dev/null | head -1)

if [ -z "$LATEST" ]; then
    fail "No eval results found in $RESULTS_DIR"
    exit 1
fi
info "Results file: $(basename "$LATEST")"

# Extract metrics using python3 (available since eval.py requires it)
METRICS=$(python3 -c "
import json, sys

with open('$LATEST') as f:
    data = json.load(f)

s = data['summary']

# Count timeouts from details
timeouts = sum(1 for d in data.get('details', []) if d.get('error') == 'timed out')

print(f\"mrr={s['avg_mrr']:.4f}\")
print(f\"source_recall={s['avg_source_recall_at_5']:.4f}\")
print(f\"keyword_recall={s['avg_keyword_recall']:.4f}\")
print(f\"timeouts={timeouts}\")
print(f\"total_queries={s['total_queries']}\")
print(f\"successful={s['successful']}\")
print(f\"errors={s['errors']}\")
print(f\"avg_latency_ms={s['avg_latency_ms']:.1f}\")
")

# Parse into variables
eval "$METRICS"

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
        if python3 -c "exit(0 if $value >= $threshold else 1)"; then
            pass "$name: $value >= $threshold"
        else
            fail "$name: $value < $threshold"
            FAILURES=$((FAILURES + 1))
        fi
    else
        if python3 -c "exit(0 if $value <= $threshold else 1)"; then
            pass "$name: $value <= $threshold"
        else
            fail "$name: $value > $threshold"
            FAILURES=$((FAILURES + 1))
        fi
    fi
}

check_threshold "MRR"              "$mrr"             "$THRESHOLD_MRR"
check_threshold "Source Recall@5"  "$source_recall"   "$THRESHOLD_SOURCE_RECALL"
check_threshold "Keyword Recall"   "$keyword_recall"  "$THRESHOLD_KEYWORD_RECALL"
check_threshold "Query Timeouts"   "$timeouts"        "$MAX_TIMEOUTS" "lte"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}PASSED${NC} — All quality gates met."
    exit 0
else
    echo -e "${RED}${BOLD}FAILED${NC} — $FAILURES threshold(s) breached."
    exit 1
fi
