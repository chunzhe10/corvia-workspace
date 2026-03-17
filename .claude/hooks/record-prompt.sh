#!/usr/bin/env bash
# Hook: UserPromptSubmit — record user prompt.
# Reads JSON from stdin (Claude Code hook protocol).

exec 2>/dev/null

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
