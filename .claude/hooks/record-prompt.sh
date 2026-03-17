#!/usr/bin/env bash
# Hook: UserPromptSubmit — record user prompt.
# Reads JSON from stdin (Claude Code hook protocol).

# Telemetry: inline capture of exit code + stderr (remove when diagnosed)
_TEL_LOG="/tmp/claude-hook-telemetry.jsonl"
_TEL_ERR=$(mktemp /tmp/_hk.XXXXXX 2>/dev/null || echo /tmp/_hk_$$)
exec 2>"$_TEL_ERR"
trap '_RC=$?; printf "{\"ts\":\"%s\",\"hook\":\"record-prompt\",\"rc\":%d,\"err\":\"%s\"}\n" "$(date -u +%H:%M:%S)" "$_RC" "$(tr "\n" " " < "$_TEL_ERR" 2>/dev/null)" >> "$_TEL_LOG" 2>/dev/null; rm -f "$_TEL_ERR"; exit $_RC' EXIT

SESSIONS_DIR="$HOME/.claude/sessions"

# Read current session ID
SESSION_ID=$(cat "$SESSIONS_DIR/.current-session-id" 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0

LOGFILE="$SESSIONS_DIR/${SESSION_ID}.jsonl"
[ ! -f "$LOGFILE" ] && exit 0

# Read stdin JSON
INPUT=$(cat)

# Extract prompt text
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')
[ -z "$PROMPT" ] && exit 0

# Increment turn counter
TURN_FILE="$SESSIONS_DIR/${SESSION_ID}.turn"
TURN=$(cat "$TURN_FILE" 2>/dev/null || echo "0")
TURN=$((TURN + 1))
echo "$TURN" > "$TURN_FILE"

# Append user_prompt event (atomic via O_APPEND)
jq -nc \
    --arg type "user_prompt" \
    --arg sid "$SESSION_ID" \
    --argjson turn "$TURN" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)" \
    --arg content "$PROMPT" \
    '{
        type: $type,
        session_id: $sid,
        turn: $turn,
        timestamp: $ts,
        content: $content
    }' >> "$LOGFILE"

exit 0
