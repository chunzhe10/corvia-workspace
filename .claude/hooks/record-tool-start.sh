#!/usr/bin/env bash
# Hook: PreToolUse — record tool invocation start.
# Reads JSON from stdin (Claude Code hook protocol).
# Does NOT block — exits 0 immediately after append.

# Telemetry: inline capture of exit code + stderr (remove when diagnosed)
_TEL_LOG="/tmp/claude-hook-telemetry.jsonl"
_TEL_ERR=$(mktemp /tmp/_hk.XXXXXX 2>/dev/null || echo /tmp/_hk_$$)
exec 2>"$_TEL_ERR"
trap '_RC=$?; printf "{\"ts\":\"%s\",\"hook\":\"record-tool-start\",\"rc\":%d,\"err\":\"%s\"}\n" "$(date -u +%H:%M:%S)" "$_RC" "$(tr "\n" " " < "$_TEL_ERR" 2>/dev/null)" >> "$_TEL_LOG" 2>/dev/null; rm -f "$_TEL_ERR"; exit $_RC' EXIT

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

# Strip large content fields (Write/Edit payloads) to avoid ARG_MAX issues
INPUT_JSON=$(echo "$INPUT" | jq -c '.tool_input | del(.content, .new_string, .old_string) // {}' 2>/dev/null || echo '{}')

# Append tool_start event
jq -nc \
    --arg type "tool_start" \
    --arg sid "$SESSION_ID" \
    --argjson turn "$TURN" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)" \
    --arg tool "$TOOL_NAME" \
    --argjson input "$INPUT_JSON" \
    '{
        type: $type,
        session_id: $sid,
        turn: $turn,
        timestamp: $ts,
        tool: $tool,
        input: $input
    }' >> "$LOGFILE"

exit 0
