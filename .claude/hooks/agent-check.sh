#!/usr/bin/env bash
# Auto-register agent identity on SessionStart.
# Calls the REST API to connect as claude-code agent.
# Falls back to display-only message if server is down.

CORVIA_API="${CORVIA_API:-http://localhost:8020}"
AGENT_ID="${CORVIA_AGENT_ID:-claude-code}"

# Try to auto-register via REST API (non-interactive)
RESPONSE=$(curl -sf --max-time 3 \
    -X POST "$CORVIA_API/api/dashboard/agents/$AGENT_ID/connect" \
    -H "Content-Type: application/json" \
    -d '{}' 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$RESPONSE" ]; then
    SESSIONS=$(echo "$RESPONSE" | jq -r '.active_sessions // 0' 2>/dev/null)
    echo "Connected as: $AGENT_ID (active sessions: ${SESSIONS:-0})"
    exit 0
fi

# Server not available — display fallback message
echo "Agent auto-registration deferred (server not ready). Will register on first MCP write."
