#!/usr/bin/env bash
# Embedding Model Benchmark for Corvia
# Compares latency, throughput, and resource usage across embedding backends.
#
# Prerequisites:
#   - corvia-inference server running on port 8030
#   - CUDA and OpenVINO backends available
#
# Usage: bash benchmarks/embedding-models/run.sh

set -euo pipefail

RESULTS_DIR="$(dirname "$0")/results"
mkdir -p "$RESULTS_DIR"

INFERENCE_URL="http://127.0.0.1:8030"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
RESULT_FILE="$RESULTS_DIR/benchmark-$TIMESTAMP.json"

echo "=== Corvia Embedding Model Benchmark ==="
echo "Timestamp: $TIMESTAMP"
echo "Results: $RESULT_FILE"
echo ""

# Test texts of varying lengths
declare -a TEXTS=(
    "What is corvia?"
    "Corvia is an organizational memory system for AI agents, built in Rust with AGPL-3.0 licensing."
    "The kernel provides storage traits (QueryableStore, TemporalStore, GraphStore), inference traits (InferenceEngine), and ingestion traits (IngestionAdapter). LiteStore implements all storage traits using JSON files, Redb for metadata, and HNSW for vector search. The architecture is local-first with zero Docker dependency."
)

# Benchmark function: embed N times and measure
benchmark_embed() {
    local text="$1"
    local iterations="$2"
    local label="$3"

    echo "  Benchmarking: $label ($iterations iterations, ${#text} chars)"

    # Use corvia search as proxy for embedding (triggers embed + search)
    local start_ns=$(date +%s%N)
    for i in $(seq 1 "$iterations"); do
        curl -sf -X POST "$INFERENCE_URL/embed" \
            -H "Content-Type: application/json" \
            -d "{\"text\": \"$text\", \"model\": \"nomic-embed-text-v1.5\"}" \
            -o /dev/null 2>/dev/null || true
    done
    local end_ns=$(date +%s%N)
    local elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
    local avg_ms=$(( elapsed_ms / iterations ))
    local throughput=$(python3 -c "print(f'{$iterations / ($elapsed_ms / 1000.0):.1f}')" 2>/dev/null || echo "N/A")

    echo "    Total: ${elapsed_ms}ms, Avg: ${avg_ms}ms, Throughput: ${throughput}/s"
    echo "{\"label\":\"$label\",\"text_len\":${#text},\"iterations\":$iterations,\"total_ms\":$elapsed_ms,\"avg_ms\":$avg_ms,\"throughput_per_s\":\"$throughput\"}"
}

# Run benchmarks via MCP search (which triggers embed internally)
echo ""
echo "--- Benchmarking via corvia search (embed + HNSW search) ---"

results="[]"
for i in "${!TEXTS[@]}"; do
    text="${TEXTS[$i]}"
    label="text_$((i+1))_${#text}chars"

    # Warm up
    curl -sf -X POST http://localhost:8020/mcp \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"corvia_search\",\"arguments\":{\"query\":\"$text\",\"scope_id\":\"corvia\",\"limit\":3}},\"id\":1}" \
        -o /dev/null 2>/dev/null || true

    # Measure 10 iterations
    start_ns=$(date +%s%N)
    for iter in $(seq 1 10); do
        curl -sf -X POST http://localhost:8020/mcp \
            -H "Content-Type: application/json" \
            -d "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"corvia_search\",\"arguments\":{\"query\":\"$text\",\"scope_id\":\"corvia\",\"limit\":5}},\"id\":$iter}" \
            -o /dev/null 2>/dev/null || true
    done
    end_ns=$(date +%s%N)
    elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
    avg_ms=$(( elapsed_ms / 10 ))

    echo "  $label: total=${elapsed_ms}ms avg=${avg_ms}ms"
done

# Collect trace data for detailed timing
echo ""
echo "--- Collecting trace timing data ---"
sleep 2
curl -sf http://localhost:8020/api/dashboard/traces/recent?limit=50 | python3 -m json.tool > "$RESULTS_DIR/traces-$TIMESTAMP.json" 2>/dev/null || true

echo ""
echo "--- Existing GPU benchmark data ---"
if [ -f "/workspaces/corvia-workspace/docs/benchmarks/embedding-backend-benchmark.md" ]; then
    echo "Found existing benchmark at docs/benchmarks/embedding-backend-benchmark.md"
    cp "/workspaces/corvia-workspace/docs/benchmarks/embedding-backend-benchmark.md" "$RESULTS_DIR/gpu-benchmark-reference.md" 2>/dev/null || true
fi

echo ""
echo "=== Benchmark complete ==="
echo "Results saved to: $RESULTS_DIR/"
