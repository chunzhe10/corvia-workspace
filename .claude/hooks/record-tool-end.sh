#!/usr/bin/env bash
# Hook: PostToolUse — record tool completion with output.
# Reads JSON from stdin (Claude Code hook protocol).
# Truncates output to 500 chars to keep logs compact.

# Telemetry: inline capture of exit code + stderr (remove when diagnosed)
_TEL_LOG="/tmp/claude-hook-telemetry.jsonl"
_TEL_ERR=$(mktemp /tmp/_hk.XXXXXX 2>/dev/null || echo /tmp/_hk_$$)
exec 2>"$_TEL_ERR"
trap '_RC=$?; printf "{\"ts\":\"%s\",\"hook\":\"record-tool-end\",\"rc\":%d,\"err\":\"%s\"}\n" "$(date -u +%H:%M:%S)" "$_RC" "$(tr "\n" " " < "$_TEL_ERR" 2>/dev/null)" >> "$_TEL_LOG" 2>/dev/null; rm -f "$_TEL_ERR"; exit $_RC' EXIT

SESSIONS_DIR="$HOME/.claude/sessions"

# Read current session ID
SESSION_ID=$(cat "$SESSIONS_DIR/.current-session-id" 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

LOGFILE="$SESSIONS_DIR/${SESSION_ID}.jsonl"
[ ! -f "$LOGFILE" ] && exit 0

# Read stdin JSON
INPUT=$(cat)

# Extract tool name
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
[ -z "$TOOL_NAME" ] && exit 0

# Skip low-signal tools
case "$TOOL_NAME" in
    health|ToolSearch) exit 0 ;;
esac

# Current turn
TURN_FILE="$SESSIONS_DIR/${SESSION_ID}.turn"
TURN=$(cat "$TURN_FILE" 2>/dev/null || echo "0")

# Extract and truncate output (500 char limit)
MAX_OUTPUT=500
OUTPUT_RAW=$(echo "$INPUT" | jq -r '.tool_response // "" | tostring')
OUTPUT_LEN=${#OUTPUT_RAW}
if [ "$OUTPUT_LEN" -gt "$MAX_OUTPUT" ]; then
    OUTPUT="${OUTPUT_RAW:0:$MAX_OUTPUT}"
    TRUNCATED="true"
else
    OUTPUT="$OUTPUT_RAW"
    TRUNCATED="false"
fi

# Compute duration placeholder (hooks don't get timing; adapter can compute from timestamps)
TS_NOW=$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)

# Strip large content fields (Write/Edit payloads) to avoid ARG_MAX issues
INPUT_JSON=$(echo "$INPUT" | jq -c '.tool_input | del(.content, .new_string, .old_string) // {}' 2>/dev/null || echo '{}')

# Append tool_end event
jq -nc \
    --arg type "tool_end" \
    --arg sid "$SESSION_ID" \
    --argjson turn "$TURN" \
    --arg ts "$TS_NOW" \
    --arg tool "$TOOL_NAME" \
    --argjson input "$INPUT_JSON" \
    --arg output "$OUTPUT" \
    --argjson truncated "$TRUNCATED" \
    --argjson success true \
    '{
        type: $type,
        session_id: $sid,
        turn: $turn,
        timestamp: $ts,
        tool: $tool,
        input: $input,
        output: $output,
        truncated: $truncated,
        success: $success
    }' >> "$LOGFILE"

exit 0
