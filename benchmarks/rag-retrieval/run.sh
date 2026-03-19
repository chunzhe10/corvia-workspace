#!/usr/bin/env bash
# RAG Retrieval Quality Benchmark for Corvia
# Tests retrieval quality using known-answer queries against corvia's own knowledge base.
#
# Prerequisites:
#   - corvia server running on port 8020
#   - Knowledge base populated (corvia workspace ingest)
#
# Usage: bash benchmarks/rag-retrieval/run.sh

set -euo pipefail

RESULTS_DIR="$(dirname "$0")/results"
mkdir -p "$RESULTS_DIR"

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
RESULT_FILE="$RESULTS_DIR/retrieval-$TIMESTAMP.json"

echo "=== Corvia RAG Retrieval Benchmark ==="
echo "Timestamp: $TIMESTAMP"
echo ""

# Known-answer test queries
# Format: "query|expected_substring_in_source_file"
declare -a QUERIES=(
    "What is the LiteStore storage format?|lite_store"
    "How does agent crash recovery work?|milestone-revision"
    "What embedding model does corvia use?|embedding"
    "How does the merge worker resolve conflicts?|merge"
    "What is the dashboard architecture?|dashboard"
    "How does temporal reasoning work?|temporal"
    "What license is corvia under?|README"
    "How are knowledge entries chunked?|chunking"
    "What MCP tools are available?|AGENTS"
    "How does graph expansion affect retrieval?|retriever"
)

total=0
recall_5=0
recall_10=0
mrr_sum=0

echo "Query | Expected | Found@5 | Found@10 | Rank | Latency"
echo "------|----------|---------|----------|------|--------"

for entry in "${QUERIES[@]}"; do
    IFS='|' read -r query expected <<< "$entry"
    total=$((total + 1))

    start_ms=$(date +%s%N)
    response=$(curl -sf -X POST http://localhost:8020/mcp \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"corvia_search\",\"arguments\":{\"query\":\"$query\",\"scope_id\":\"corvia\",\"limit\":10}},\"id\":$total}" 2>/dev/null || echo '{"error":"timeout"}')
    end_ms=$(date +%s%N)
    latency_ms=$(( (end_ms - start_ms) / 1000000 ))

    # Parse results to check if expected source appears
    found_at=$(echo "$response" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    results = json.loads(d.get('result',{}).get('content',[{}])[0].get('text','[]'))
    for i, r in enumerate(results):
        src = r.get('source_file','') + r.get('source','')
        if '$expected' in src.lower():
            print(i+1)
            sys.exit(0)
    print(0)
except:
    print(0)
" 2>/dev/null || echo "0")

    in_5="NO"
    in_10="NO"
    if [ "$found_at" -gt 0 ] && [ "$found_at" -le 5 ]; then
        in_5="YES"
        in_10="YES"
        recall_5=$((recall_5 + 1))
        recall_10=$((recall_10 + 1))
        mrr_sum=$(python3 -c "print($mrr_sum + 1.0/$found_at)")
    elif [ "$found_at" -gt 5 ] && [ "$found_at" -le 10 ]; then
        in_10="YES"
        recall_10=$((recall_10 + 1))
        mrr_sum=$(python3 -c "print($mrr_sum + 1.0/$found_at)")
    fi

    printf "%-45s | %-15s | %-7s | %-8s | %-4s | %dms\n" \
        "${query:0:45}" "$expected" "$in_5" "$in_10" "$found_at" "$latency_ms"
done

echo ""
echo "=== Summary ==="
echo "Total queries: $total"
echo "Recall@5:  $recall_5/$total ($(python3 -c "print(f'{$recall_5/$total*100:.0f}%')"))"
echo "Recall@10: $recall_10/$total ($(python3 -c "print(f'{$recall_10/$total*100:.0f}%')"))"
echo "MRR:       $(python3 -c "print(f'{$mrr_sum/$total:.3f}')")"

# Save results as JSON
python3 -c "
import json
results = {
    'timestamp': '$TIMESTAMP',
    'total_queries': $total,
    'recall_at_5': $recall_5,
    'recall_at_10': $recall_10,
    'mrr': $mrr_sum / $total,
    'knowledge_base_size': 8769
}
with open('$RESULT_FILE', 'w') as f:
    json.dump(results, f, indent=2)
print(f'Results saved to {\"$RESULT_FILE\"}')" 2>/dev/null || true

echo ""
echo "=== Benchmark complete ==="
