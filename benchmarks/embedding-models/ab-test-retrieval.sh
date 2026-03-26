#!/usr/bin/env bash
# Embedding Model A/B Test — Retrieval Quality Comparison
#
# Compares retrieval quality between two embedding models by running the full
# eval suite with each model. Requires server restart + re-ingestion between
# models (embedding config is not hot-reloadable).
#
# WARNING: This test takes several minutes due to re-ingestion. Not suitable for CI.
#
# Usage:
#   bash benchmarks/embedding-models/ab-test-retrieval.sh
#
# Prerequisites:
#   - corvia server + inference server running
#   - Knowledge base ingested

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TOML="$WORKSPACE_ROOT/corvia.toml"
TOML_BAK="$TOML.ab-test-bak"
EVAL_SCRIPT="$WORKSPACE_ROOT/benchmarks/rag-retrieval/eval.py"
RESULTS_DIR="$SCRIPT_DIR/results"
SERVER="${CORVIA_SERVER:-http://localhost:8020}"

# Models to compare
MODEL_A_NAME="nomic-embed-text-v1.5"
MODEL_A_DIM=768
MODEL_B_NAME="all-MiniLM-L6-v2"
MODEL_B_DIM=384

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)

# Track PIDs for clean shutdown
INFERENCE_PID=""
SERVER_PID=""

cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    # Kill processes we started (by PID, not pkill)
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
    [ -n "$INFERENCE_PID" ] && kill "$INFERENCE_PID" 2>/dev/null || true
    if [ -f "$TOML_BAK" ]; then
        cp "$TOML_BAK" "$TOML"
        rm -f "$TOML_BAK"
        echo -e "${YELLOW}Config restored. You may need to restart servers and re-ingest manually:${NC}"
        echo "  corvia-dev down && corvia-dev up --no-foreground"
        echo "  corvia workspace ingest --fresh"
    fi
}
trap cleanup EXIT

wait_for_server() {
    local port="$1"
    local name="$2"
    local max_wait="${3:-60}"
    echo "  Waiting for $name on port $port..."
    for i in $(seq 1 "$max_wait"); do
        if curl -sf --max-time 2 "http://127.0.0.1:$port/health" > /dev/null 2>&1; then
            echo "  $name ready"
            return 0
        fi
        sleep 1
    done
    echo "  ERROR: $name did not start within ${max_wait}s"
    return 1
}

stop_servers() {
    echo "  Stopping servers..."
    [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
    [ -n "$INFERENCE_PID" ] && kill "$INFERENCE_PID" 2>/dev/null || true
    SERVER_PID=""
    INFERENCE_PID=""
    sleep 2
}

start_servers() {
    cd "$WORKSPACE_ROOT/repos/corvia" && ./target/release/corvia-inference >> /tmp/ab-test-inference.log 2>&1 &
    INFERENCE_PID=$!
    wait_for_server 8030 "inference"

    cd "$WORKSPACE_ROOT" && repos/corvia/target/release/corvia serve >> /tmp/ab-test-server.log 2>&1 &
    SERVER_PID=$!
    wait_for_server 8020 "corvia"
}

restart_servers() {
    stop_servers
    start_servers
}

# ── Preflight ────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}=== Embedding Model A/B Test ===${NC}"
echo "Model A: $MODEL_A_NAME (${MODEL_A_DIM}d)"
echo "Model B: $MODEL_B_NAME (${MODEL_B_DIM}d)"
echo "Server: $SERVER"
echo ""

if [ ! -f "$EVAL_SCRIPT" ]; then
    echo -e "${RED}ERROR${NC}: Eval script not found at $EVAL_SCRIPT"
    exit 1
fi

if [ ! -f "$TOML" ]; then
    echo -e "${RED}ERROR${NC}: corvia.toml not found at $TOML"
    exit 1
fi

# Save backup
cp "$TOML" "$TOML_BAK"
mkdir -p "$RESULTS_DIR"

# ── Model A ──────────────────────────────────────────────────────────────────
echo -e "${BOLD}[1/5] Running eval with $MODEL_A_NAME${NC}"
RESULT_A="$RESULTS_DIR/model-${MODEL_A_NAME}-${TIMESTAMP}.json"

# Clean eval results to ensure we get fresh output
rm -f "$WORKSPACE_ROOT/benchmarks/rag-retrieval/results"/eval-*.json

python3 "$EVAL_SCRIPT" --server "$SERVER" --limit 10
LATEST_A=$(ls -t "$WORKSPACE_ROOT/benchmarks/rag-retrieval/results"/eval-*.json 2>/dev/null | head -1)
if [ -z "$LATEST_A" ]; then
    echo -e "${RED}ERROR${NC}: No eval results for Model A"
    exit 1
fi
cp "$LATEST_A" "$RESULT_A"
echo -e "${GREEN}Model A results saved: $(basename "$RESULT_A")${NC}"

# ── Switch to Model B ────────────────────────────────────────────────────────
echo -e "\n${BOLD}[2/5] Switching to $MODEL_B_NAME${NC}"

# Patch corvia.toml
python3 - "$TOML" "$MODEL_B_NAME" "$MODEL_B_DIM" <<'PYEOF'
import sys

toml_path, model_name, dimensions = sys.argv[1], sys.argv[2], sys.argv[3]

with open(toml_path) as f:
    content = f.read()

# Replace model and dimensions in [embedding] section
import re
content = re.sub(r'(model\s*=\s*)"[^"]*"', f'\\1"{model_name}"', content, count=1)
content = re.sub(r'(dimensions\s*=\s*)\d+', f'\\1{dimensions}', content, count=1)

with open(toml_path, "w") as f:
    f.write(content)

print(f"  Updated corvia.toml: model={model_name}, dimensions={dimensions}")
PYEOF

# ── Restart + Re-ingest ──────────────────────────────────────────────────────
echo -e "\n${BOLD}[3/5] Restarting servers and re-ingesting${NC}"
restart_servers

echo "  Re-ingesting with --fresh (new embeddings)..."
"$WORKSPACE_ROOT/repos/corvia/target/release/corvia" workspace ingest --fresh
echo -e "${GREEN}Re-ingestion complete${NC}"

# ── Model B ──────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}[4/5] Running eval with $MODEL_B_NAME${NC}"
RESULT_B="$RESULTS_DIR/model-${MODEL_B_NAME}-${TIMESTAMP}.json"

rm -f "$WORKSPACE_ROOT/benchmarks/rag-retrieval/results"/eval-*.json

python3 "$EVAL_SCRIPT" --server "$SERVER" --limit 10
LATEST_B=$(ls -t "$WORKSPACE_ROOT/benchmarks/rag-retrieval/results"/eval-*.json 2>/dev/null | head -1)
if [ -z "$LATEST_B" ]; then
    echo -e "${RED}ERROR${NC}: No eval results for Model B"
    exit 1
fi
cp "$LATEST_B" "$RESULT_B"
echo -e "${GREEN}Model B results saved: $(basename "$RESULT_B")${NC}"

# ── Restore + Compare ────────────────────────────────────────────────────────
echo -e "\n${BOLD}[5/5] Restoring original config and comparing${NC}"

# Restore is handled by trap, but let's be explicit
cp "$TOML_BAK" "$TOML"

# Restart with original model
restart_servers
echo "  Re-ingesting with original model..."
"$WORKSPACE_ROOT/repos/corvia/target/release/corvia" workspace ingest --fresh
echo -e "${GREEN}Original state restored${NC}"

# Run comparison
echo ""
python3 "$SCRIPT_DIR/compare-models.py" "$RESULT_A" "$RESULT_B" \
    --model-a "$MODEL_A_NAME" --model-b "$MODEL_B_NAME"

echo -e "\n${BOLD}Done.${NC} Results in: $RESULTS_DIR/"
