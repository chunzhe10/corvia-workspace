#!/usr/bin/env bash
# Hook: SessionStart — initialize session recording.
# Creates ~/.claude/sessions/<session-id>.jsonl with a session_start event.
# Reads JSON from stdin (Claude Code hook protocol).

exec 2>/dev/null

SESSIONS_DIR="$HOME/.claude/sessions"
mkdir -p "$SESSIONS_DIR"

# Read stdin JSON
INPUT=$(cat)

# Extract session_id from hook JSON (Claude Code provides it)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
if [ -z "$SESSION_ID" ]; then
    # Fallback: generate our own
    SESSION_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "ses-$$-$(date +%s)")
fi

# Write current session ID for other hooks to read
echo "$SESSION_ID" > "$SESSIONS_DIR/.current-session-id"

# Detect agent type from hook JSON
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')
AGENT_ID_FIELD=$(echo "$INPUT" | jq -r '.agent_id // empty')

# If agent_id is present, this is a subagent
if [ -n "$AGENT_ID_FIELD" ]; then
    AGENT_TYPE_VAL="subagent"
    # For subagents, try to read the parent session from the main session file
    PARENT_SESSION_ID=""
else
    AGENT_TYPE_VAL="main"
    PARENT_SESSION_ID=""
fi

# Override with explicit agent_type if it looks like a named agent
if [ -n "$AGENT_TYPE" ] && [ "$AGENT_TYPE" != "null" ]; then
    AGENT_TYPE_VAL="$AGENT_TYPE"
fi

# Workspace from cwd
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && CWD="$PWD"

# Git branch
GIT_BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# Corvia agent identity
CORVIA_AGENT="${CORVIA_AGENT_ID:-}"

# Initialize turn counter
echo "0" > "$SESSIONS_DIR/${SESSION_ID}.turn"

# Write session_start event
LOGFILE="$SESSIONS_DIR/${SESSION_ID}.jsonl"
jq -nc \
    --arg type "session_start" \
    --arg sid "$SESSION_ID" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)" \
    --arg ws "$CWD" \
    --arg branch "$GIT_BRANCH" \
    --arg atype "$AGENT_TYPE_VAL" \
    --arg parent "$PARENT_SESSION_ID" \
    --arg agent "$CORVIA_AGENT" \
    '{
        type: $type,
        session_id: $sid,
        timestamp: $ts,
        workspace: $ws,
        git_branch: $branch,
        agent_type: $atype,
        parent_session_id: (if $parent == "" then null else $parent end),
        corvia_agent_id: (if $agent == "" then null else $agent end)
    }' >> "$LOGFILE"

exit 0
