#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Prevent duplicate/concurrent runs.
# The lock dir prevents concurrent execution; the done marker prevents re-runs
# after a successful completion (VS Code fires postStartCommand on each connect).
LOCK_FILE="/tmp/corvia-post-start.lock"
# Use boot ID so the done marker is invalidated on container restart
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo "unknown")
DONE_MARKER="/tmp/corvia-post-start.done"

if [ -f "$DONE_MARKER" ] && [ "$(cat "$DONE_MARKER" 2>/dev/null)" = "$BOOT_ID" ]; then
    echo "post-start.sh already completed this boot. Skipping."
    exit 0
fi
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
    echo "post-start.sh is already running (lock: $LOCK_FILE). Skipping."
    exit 0
fi
trap 'rmdir "$LOCK_FILE" 2>/dev/null' EXIT

step() { printf " => %s\n" "$*"; }
done_msg() { printf "    ... done\n"; }
skip_msg() { printf "    ... skipped (%s)\n" "$*"; }
fail_msg() { printf "    ... FAILED (%s)\n" "$*" >&2; }

FLAGS_FILE="$WORKSPACE_ROOT/.devcontainer/.corvia-workspace-flags"

echo "=== Corvia Workspace: post-start ==="

# ── 1/4 ───────────────────────────────────────────────────────────────
step "Forwarding host authentication"
forward_host_auth

# ── 2/4 ───────────────────────────────────────────────────────────────
step "Starting corvia-dev services"
if ! command -v corvia-dev >/dev/null 2>&1; then
    echo "    corvia-dev not found — running ensure_tooling"
    ensure_tooling
fi
if command -v corvia-dev >/dev/null 2>&1; then
    if corvia-dev status --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('manager',{}).get('state')=='running' else 1)" 2>/dev/null; then
        echo "    manager already running"
    else
        corvia-dev up --no-foreground
        echo "    manager started"
    fi
else
    fail_msg "corvia-dev not available — run ensure_tooling manually"
fi

printf "    waiting for MCP server (port 8020)"
mcp_ready=false
for _attempt in $(seq 1 30); do
    if curl -sf --max-time 2 -o /dev/null http://127.0.0.1:8020/mcp 2>/dev/null; then
        done_msg
        mcp_ready=true
        break
    fi
    printf "."
    sleep 2
done
if [ "$mcp_ready" = false ]; then
    fail_msg "not ready after 60s — check 'corvia-dev logs corvia-server'"
fi

# ── 3/4 ───────────────────────────────────────────────────────────────
step "Claude Code integration"
# MCP server is configured via .mcp.json in the workspace root (checked into git).
# No need to call 'claude mcp add' — Claude Code reads .mcp.json directly.
MCP_JSON="$WORKSPACE_ROOT/.mcp.json"
if [ -f "$MCP_JSON" ] && python3 -c "import json; d=json.load(open('$MCP_JSON')); assert 'corvia' in d.get('mcpServers',{})" 2>/dev/null; then
    echo "    MCP server configured via .mcp.json"
else
    echo "    writing .mcp.json"
    python3 -c "
import json, os
p = '$MCP_JSON'
d = json.load(open(p)) if os.path.exists(p) else {}
d.setdefault('mcpServers', {})['corvia'] = {'type': 'http', 'url': 'http://127.0.0.1:8020/mcp'}
json.dump(d, open(p, 'w'), indent=2)
print('    MCP server added to .mcp.json')
"
fi

# Install superpowers plugin via direct git clone (no claude CLI dependency)
printf "    superpowers plugin: "
install_claude_plugin "https://github.com/obra/superpowers.git" superpowers claude-plugins-official \
    || fail_msg "git clone failed — check network connectivity"

# ── 4/4 ───────────────────────────────────────────────────────────────
step "Optional services"
if [ -f "$FLAGS_FILE" ]; then
    if grep -q "ollama=enabled" "$FLAGS_FILE"; then
        if command -v ollama >/dev/null 2>&1; then
            printf "    starting Ollama"
            ollama serve &
            ollama_ready=false
            for i in $(seq 1 30); do
                if curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
                    done_msg
                    ollama_ready=true
                    break
                fi
                printf "."
                sleep 1
            done
            if [ "$ollama_ready" = false ]; then
                fail_msg "not ready after 30s"
            fi
        else
            fail_msg "ollama not installed — run 'curl -fsSL https://ollama.com/install.sh | sh'"
        fi
    fi
    if grep -q "surrealdb=enabled" "$FLAGS_FILE"; then
        if command -v docker >/dev/null 2>&1; then
            printf "    starting SurrealDB"
            docker compose -f "$WORKSPACE_ROOT/repos/corvia/docker/docker-compose.yml" up -d >/dev/null 2>&1 \
                && done_msg || fail_msg "docker compose up"
        else
            fail_msg "docker not available — SurrealDB requires Docker"
        fi
    fi
    if ! grep -qE "(ollama|surrealdb)=enabled" "$FLAGS_FILE"; then
        echo "    none enabled"
    fi
else
    echo "    none enabled"
fi

echo "$BOOT_ID" > "$DONE_MARKER"

echo ""
echo "Ready. Run 'corvia-dev status' to check services."
