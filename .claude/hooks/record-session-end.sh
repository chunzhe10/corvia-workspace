#!/usr/bin/env bash
# Hook: SessionEnd — finalize session log, compress, trigger ingest.
# Writes session_end event, gzips the JSONL, optionally triggers corvia ingest.

exec 2>/dev/null

SESSIONS_DIR="$HOME/.claude/sessions"

# Read current session ID
SESSION_ID=$(cat "$SESSIONS_DIR/.current-session-id" 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

LOGFILE="$SESSIONS_DIR/${SESSION_ID}.jsonl"
[ ! -f "$LOGFILE" ] && exit 0

# Read turn count
TURN_FILE="$SESSIONS_DIR/${SESSION_ID}.turn"
TOTAL_TURNS=$(cat "$TURN_FILE" 2>/dev/null || echo "0")

# Read stdin for session metadata
INPUT=$(cat 2>/dev/null || echo "{}")

# Read session_start timestamp from first line to compute duration
START_TS=$(head -1 "$LOGFILE" | jq -r '.timestamp // empty')
END_TS=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)

# Compute duration in ms (best effort)
DURATION_MS=0
if [ -n "$START_TS" ] && command -v date >/dev/null; then
    START_EPOCH=$(date -d "$START_TS" +%s 2>/dev/null || echo "0")
    END_EPOCH=$(date -u +%s)
    if [ "$START_EPOCH" -gt 0 ] 2>/dev/null; then
        DURATION_MS=$(( (END_EPOCH - START_EPOCH) * 1000 ))
    fi
fi

# Append session_end event
jq -nc \
    --arg type "session_end" \
    --arg sid "$SESSION_ID" \
    --arg ts "$END_TS" \
    --argjson turns "$TOTAL_TURNS" \
    --argjson duration "$DURATION_MS" \
    '{
        type: $type,
        session_id: $sid,
        timestamp: $ts,
        total_turns: $turns,
        duration_ms: $duration
    }' >> "$LOGFILE"

# Gzip the log
gzip -f "$LOGFILE" 2>/dev/null

# Cleanup turn counter
rm -f "$TURN_FILE"

# Trigger corvia ingest (best-effort, non-blocking)
# The adapter will process ~/.claude/sessions/*.jsonl.gz
if command -v corvia >/dev/null 2>&1; then
    corvia workspace ingest --quiet 2>/dev/null &
fi

exit 0
