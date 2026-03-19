#!/bin/bash
# Embedding benchmark: CPU vs Intel iGPU (OpenVINO) vs NVIDIA GPU (CUDA)
# Uses corvia's gRPC inference server with nomic-embed-text-v1.5 (768d)
# Apple-to-apple: same model, same input, same code path, only EP differs.
set -euo pipefail

cd /workspaces/corvia-workspace

GRPC_URL="http://127.0.0.1:8030"
MODEL="nomic-embed-text-v1.5"
RESULTS_FILE="/tmp/embedding-benchmark-results.md"

# Fixed test corpus — diverse lengths and content types
TEXTS=(
    "The HNSW algorithm constructs a multi-layer graph for approximate nearest neighbor search."
    "Embedding models convert text into dense vector representations that capture semantic meaning."
    "Intel Iris Xe Graphics features 96 execution units with a maximum clock speed of 1400 MHz."
    "ONNX Runtime supports multiple execution providers including CUDA, OpenVINO, and TensorRT."
    "Knowledge graphs represent relationships between entities using directed edges with typed relations."
    "The Rust programming language provides memory safety guarantees without garbage collection overhead."
    "Retrieval-augmented generation combines vector search with language model inference for grounded answers."
    "Docker containers provide lightweight isolation using Linux namespaces and cgroups for resource management."
    "Bi-temporal databases track both valid time and transaction time for complete historical queries."
    "The transformer architecture uses self-attention mechanisms to process sequential data in parallel."
    "Cosine similarity measures the angle between two vectors, commonly used for comparing embeddings."
    "gRPC uses Protocol Buffers for efficient binary serialization with strong typing and code generation."
    "Tree-sitter generates concrete syntax trees for incremental parsing of source code in multiple languages."
    "The merge worker detects semantic conflicts between concurrent knowledge entries using similarity thresholds."
    "Level Zero is Intel's low-level GPU programming API providing direct hardware access for compute workloads."
    "Agent coordination requires session isolation, branch-per-agent staging, and idempotent merge pipelines."
)

NUM_TEXTS=${#TEXTS[@]}
ITERATIONS=3  # runs per backend

# Helper: embed a single text via gRPC and return latency in ms
embed_single() {
    local text="$1"
    local start end elapsed_ms
    start=$(date +%s%N)
    # Use the corvia search which goes through the full embed path
    # Actually, let's use grpcurl or a direct HTTP call for precise measurement
    # Since we have the corvia CLI, use it to embed
    corvia embed "$text" >/dev/null 2>&1
    end=$(date +%s%N)
    elapsed_ms=$(( (end - start) / 1000000 ))
    echo "$elapsed_ms"
}

# Helper: embed all texts sequentially and return total time
benchmark_sequential() {
    local total_ms=0
    local start end
    start=$(date +%s%N)
    for text in "${TEXTS[@]}"; do
        corvia embed "$text" >/dev/null 2>&1
    done
    end=$(date +%s%N)
    total_ms=$(( (end - start) / 1000000 ))
    echo "$total_ms"
}

# Helper: run full benchmark for current backend
run_benchmark() {
    local backend_name="$1"
    local results=()

    echo "  Warming up..."
    corvia embed "warmup embedding test" >/dev/null 2>&1
    corvia embed "second warmup" >/dev/null 2>&1
    sleep 1

    echo "  Running $ITERATIONS iterations of $NUM_TEXTS sequential embeddings..."
    for i in $(seq 1 $ITERATIONS); do
        local ms
        ms=$(benchmark_sequential)
        results+=("$ms")
        local per_embed=$(( ms / NUM_TEXTS ))
        echo "    Run $i: ${ms}ms total, ${per_embed}ms/embed"
    done

    # Calculate mean and stddev
    local sum=0
    for r in "${results[@]}"; do
        sum=$((sum + r))
    done
    local mean=$((sum / ITERATIONS))
    local mean_per=$((mean / NUM_TEXTS))

    local variance_sum=0
    for r in "${results[@]}"; do
        local diff=$((r - mean))
        variance_sum=$((variance_sum + diff * diff))
    done
    local stddev
    stddev=$(python3 -c "import math; print(int(math.sqrt($variance_sum / $ITERATIONS)))")
    local stddev_per=$((stddev / NUM_TEXTS))

    echo "  => Mean: ${mean}ms total, ${mean_per}ms/embed (±${stddev_per}ms)"
    echo ""

    # Store for results table
    echo "${backend_name}|${mean}|${mean_per}|${stddev}|${stddev_per}" >> /tmp/bench_results.txt
}

# Check corvia embed command exists
if ! corvia embed --help >/dev/null 2>&1; then
    echo "corvia embed not available, using search-based benchmark"
    # Fall back to search which also triggers embedding
    embed_single() {
        local text="$1"
        local start end elapsed_ms
        start=$(date +%s%N)
        corvia search "$text" >/dev/null 2>&1
        end=$(date +%s%N)
        elapsed_ms=$(( (end - start) / 1000000 ))
        echo "$elapsed_ms"
    }
    benchmark_sequential() {
        local start end
        start=$(date +%s%N)
        for text in "${TEXTS[@]}"; do
            corvia search "$text" >/dev/null 2>&1
        done
        end=$(date +%s%N)
        echo "$(( ($(date +%s%N) - start) / 1000000 ))"
    }
fi

rm -f /tmp/bench_results.txt

echo "================================================================"
echo "  Embedding Benchmark: CPU vs Intel iGPU vs NVIDIA GPU"
echo "  Model: $MODEL (768 dimensions)"
echo "  Corpus: $NUM_TEXTS texts, $ITERATIONS iterations per backend"
echo "================================================================"
echo ""

# Verify inference is running
corvia inference status 2>&1 || { echo "Inference not running!"; exit 1; }
echo ""

# ── Backend 1: CPU ──────────────────────────────────────────────────
echo "▶ Backend: CPU"
corvia inference reload --backend cpu --no-persist 2>&1 | grep -E "Reloaded|error" || true
sleep 2
corvia inference status 2>&1 | grep nomic
run_benchmark "CPU"

# ── Backend 2: Intel iGPU (OpenVINO) ───────────────────────────────
echo "▶ Backend: Intel iGPU (OpenVINO)"
corvia inference reload --backend openvino --no-persist 2>&1 | grep -E "Reloaded|error" || true
sleep 2
corvia inference status 2>&1 | grep nomic
run_benchmark "Intel iGPU (OpenVINO)"

# ── Backend 3: NVIDIA GPU (CUDA) ───────────────────────────────────
echo "▶ Backend: NVIDIA GPU (CUDA)"
corvia inference reload --backend cuda --no-persist 2>&1 | grep -E "Reloaded|error" || true
sleep 2
corvia inference status 2>&1 | grep nomic
run_benchmark "NVIDIA GPU (CUDA)"

# ── Restore original config ─────────────────────────────────────────
echo "Restoring openvino embedding backend..."
corvia inference reload --backend openvino --no-persist 2>&1 | grep -E "Reloaded" || true

# ── Results table ────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "                      RESULTS SUMMARY"
echo "================================================================"
echo ""
echo "| Backend | Total (${NUM_TEXTS} embeds) | Per Embed | Std Dev |"
echo "|---------|-----------------|-----------|---------|"
while IFS='|' read -r name total per std std_per; do
    printf "| %-23s | %6sms | %5sms | ±%4sms |\n" "$name" "$total" "$per" "$std_per"
done < /tmp/bench_results.txt
echo ""

# Save to markdown
{
    echo "# Embedding Benchmark Results"
    echo ""
    echo "**Date**: $(date -u '+%Y-%m-%d %H:%M UTC')"
    echo "**Model**: $MODEL (768d)"
    echo "**Corpus**: $NUM_TEXTS texts, $ITERATIONS iterations per backend"
    echo "**Hardware**: Intel Iris Xe (96 EU, 1400 MHz) + NVIDIA ($(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'unknown'))"
    echo ""
    echo "| Backend | Total (${NUM_TEXTS} embeds) | Per Embed | Std Dev |"
    echo "|---------|-----------------|-----------|---------|"
    while IFS='|' read -r name total per std std_per; do
        printf "| %-23s | %6sms | %5sms | ±%4sms |\n" "$name" "$total" "$per" "$std_per"
    done < /tmp/bench_results.txt
    echo ""
} > "$RESULTS_FILE"

echo "Results saved to $RESULTS_FILE"
