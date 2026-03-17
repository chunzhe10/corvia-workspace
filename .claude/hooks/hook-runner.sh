#!/usr/bin/env bash
# Hook runner: wraps all hooks with telemetry to diagnose "hook error" failures.
# Usage: bash .claude/hooks/hook-runner.sh <hook-script> [args...]
#
# Captures: timestamp, hook name, stdin size, exit code, duration, stderr.
# Logs to /tmp/claude-hook-telemetry.jsonl (JSONL, one line per invocation).

HOOK_SCRIPT="$1"
shift

LOG="/tmp/claude-hook-telemetry.jsonl"
START_NS=$(date +%s%N 2>/dev/null || date +%s)

# Save stdin to temp file so we can measure it AND pass it to the hook
STDIN_TMP=$(mktemp /tmp/hook-stdin.XXXXXX)
cat > "$STDIN_TMP"
STDIN_SIZE=$(wc -c < "$STDIN_TMP")

# Run the actual hook, capturing stderr separately
STDERR_TMP=$(mktemp /tmp/hook-stderr.XXXXXX)
bash "$HOOK_SCRIPT" "$@" < "$STDIN_TMP" 2>"$STDERR_TMP"
RC=$?

END_NS=$(date +%s%N 2>/dev/null || date +%s)

# Compute duration in ms (best-effort — %N may not be available)
if [ ${#START_NS} -gt 10 ]; then
    DURATION_MS=$(( (END_NS - START_NS) / 1000000 ))
else
    DURATION_MS=$(( (END_NS - START_NS) * 1000 ))
fi

# Capture stderr content (first 200 chars)
STDERR_CONTENT=$(head -c 200 "$STDERR_TMP")
STDERR_SIZE=$(wc -c < "$STDERR_TMP")

# Extract tool name from stdin JSON (best-effort)
TOOL_NAME=$(jq -r '.tool_name // "unknown"' < "$STDIN_TMP" 2>/dev/null || echo "unknown")

# Log as JSONL
jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
    --arg hook "$HOOK_SCRIPT" \
    --arg tool "$TOOL_NAME" \
    --argjson rc "$RC" \
    --argjson stdin_bytes "$STDIN_SIZE" \
    --argjson stderr_bytes "$STDERR_SIZE" \
    --argjson duration_ms "$DURATION_MS" \
    --arg stderr "$STDERR_CONTENT" \
    '{ts: $ts, hook: $hook, tool: $tool, rc: $rc, stdin_bytes: $stdin_bytes, stderr_bytes: $stderr_bytes, duration_ms: $duration_ms, stderr: $stderr}' \
    >> "$LOG" 2>/dev/null

# Cleanup
rm -f "$STDIN_TMP" "$STDERR_TMP"

# Forward the original exit code
exit $RC
