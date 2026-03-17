#!/usr/bin/env bash
# Hook: PreToolUse — record tool invocation start.
# Reads JSON from stdin (Claude Code hook protocol).
# Does NOT block — exits 0 immediately after append.

exec 2>/dev/null

SESSIONS_DIR="$HOME/.claude/sessions"

# Read current session ID
SESSION_ID=$(cat "$SESSIONS_DIR/.current-session-id" 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

LOGFILE="$SESSIONS_DIR/${SESSION_ID}.jsonl"
[ ! -f "$LOGFILE" ] && exit 0

# Read stdin JSON
INPUT=$(cat)

# Extract tool name and input
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ -z "$TOOL_NAME" ] && exit 0

# Current turn
TURN_FILE="$SESSIONS_DIR/${SESSION_ID}.turn"
TURN=$(cat "$TURN_FILE" 2>/dev/null || echo "0")

# Append tool_start event
jq -nc \
    --arg type "tool_start" \
    --arg sid "$SESSION_ID" \
    --argjson turn "$TURN" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)" \
    --arg tool "$TOOL_NAME" \
    --argjson input "$(echo "$INPUT" | jq -c '.tool_input // {}')" \
    '{
        type: $type,
        session_id: $sid,
        turn: $turn,
        timestamp: $ts,
        tool: $tool,
        input: $input
    }' >> "$LOGFILE"

exit 0
