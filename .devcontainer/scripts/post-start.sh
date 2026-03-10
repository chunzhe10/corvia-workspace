#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

echo "=== Corvia Workspace: Starting Services ==="

FLAGS_FILE="$WORKSPACE_ROOT/.devcontainer/.corvia-workspace-flags"

# Install local VS Code extensions first (local, no network needed)
EXTENSIONS_DIR="$WORKSPACE_ROOT/.devcontainer/extensions"
if [ -d "$EXTENSIONS_DIR" ] && command -v code >/dev/null 2>&1; then
    for vsix in "$EXTENSIONS_DIR"/*/*.vsix; do
        [ -f "$vsix" ] || continue
        echo "Installing local extension: $(basename "$vsix")"
        code --install-extension "$vsix" --force 2>/dev/null || true
    done
fi

# Ensure all tooling is installed (catches up if post-create was incomplete)
ensure_tooling

# Start corvia-dev manager
if corvia-dev status --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('manager',{}).get('state')=='running' else 1)" 2>/dev/null; then
    echo "corvia-dev manager already running"
else
    corvia-dev up --no-foreground
    sleep 2
    echo "corvia-dev manager started"
fi

# Register MCP server with Claude Code (user-level, persists across sessions)
if command -v claude >/dev/null 2>&1; then
    claude mcp add --transport http corvia http://127.0.0.1:8020/mcp 2>/dev/null \
        && echo "Registered corvia MCP server with Claude Code" \
        || echo "  (claude mcp add failed — MCP may already be registered)"
fi

# Re-start any previously enabled optional services
if [ -f "$FLAGS_FILE" ]; then
    if grep -q "ollama=enabled" "$FLAGS_FILE"; then
        echo "Starting Ollama (previously enabled)..."
        ollama serve &
        for i in $(seq 1 30); do
            curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
            sleep 1
        done
        if ! curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
            err "Ollama failed to start within 30 seconds"
            exit 1
        fi
    fi
    if grep -q "surrealdb=enabled" "$FLAGS_FILE"; then
        echo "Starting SurrealDB (previously enabled)..."
        docker compose -f "$WORKSPACE_ROOT/repos/corvia/docker/docker-compose.yml" up -d
    fi
fi

echo "Run 'corvia-dev status' to check services."
