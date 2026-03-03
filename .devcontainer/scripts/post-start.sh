#!/bin/bash
set -e

echo "=== Corvia Workspace: Starting Services ==="

WORKSPACE_ROOT="$(pwd)"
FLAGS_FILE="$WORKSPACE_ROOT/.devcontainer/.corvia-workspace-flags"

# Start Corvia server (always — uses corvia-inference automatically when provider=corvia)
corvia serve --mcp &
echo "Corvia server running on http://localhost:8020"

# Re-start any previously enabled optional services
if [ -f "$FLAGS_FILE" ]; then
    if grep -q "ollama=enabled" "$FLAGS_FILE"; then
        echo "Starting Ollama (previously enabled)..."
        ollama serve &
        for i in $(seq 1 30); do
            curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && break
            sleep 1
        done
    fi
    if grep -q "surrealdb=enabled" "$FLAGS_FILE"; then
        echo "Starting SurrealDB (previously enabled)..."
        docker compose -f "$WORKSPACE_ROOT/repos/corvia/docker/docker-compose.yml" up -d
    fi
fi

echo "Run 'corvia-workspace status' to check services."
