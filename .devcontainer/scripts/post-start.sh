#!/bin/bash
set -euo pipefail

err() { echo "Error: $*" >&2; }

echo "=== Corvia Workspace: Starting Services ==="

WORKSPACE_ROOT="${CORVIA_WORKSPACE:-$(pwd)}"
FLAGS_FILE="$WORKSPACE_ROOT/.devcontainer/.corvia-workspace-flags"

CORVIA_BIN="/usr/local/bin/corvia"
if [ ! -x "$CORVIA_BIN" ]; then
    err "corvia binary not found at $CORVIA_BIN. Run post-create.sh or 'corvia-workspace rebuild' first."
    exit 1
fi

# Start Corvia server (always — uses corvia-inference automatically when provider=corvia)
"$CORVIA_BIN" serve --mcp &
CORVIA_PID=$!
sleep 1
if ! kill -0 "$CORVIA_PID" 2>/dev/null; then
    err "Corvia server failed to start."
    exit 1
fi
echo "Corvia server running on http://localhost:8020 (pid $CORVIA_PID)"

# Register MCP server with Claude Code (user-level, persists across sessions)
if command -v claude >/dev/null 2>&1; then
    claude mcp add corvia -t http -u http://localhost:8020/mcp 2>/dev/null \
        && echo "Registered corvia MCP server with Claude Code" \
        || echo "  (claude mcp add failed — MCP may already be registered)"
fi

# Re-start any previously enabled optional services
if [ -f "$FLAGS_FILE" ]; then
    if grep -q "ollama=enabled" "$FLAGS_FILE"; then
        echo "Starting Ollama (previously enabled)..."
        ollama serve &
        for i in $(seq 1 30); do
            curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && break
            sleep 1
        done
        if ! curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
            err "Ollama failed to start within 30 seconds"
            exit 1
        fi
    fi
    if grep -q "surrealdb=enabled" "$FLAGS_FILE"; then
        echo "Starting SurrealDB (previously enabled)..."
        docker compose -f "$WORKSPACE_ROOT/repos/corvia/docker/docker-compose.yml" up -d
    fi
fi

echo "Run 'corvia-workspace status' to check services."
