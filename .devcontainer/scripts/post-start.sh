#!/bin/bash
# LEGACY FALLBACK — this script is used only when the `task` binary is unavailable.
# The primary setup orchestration is in .devcontainer/Taskfile.yml, invoked by
# .devcontainer/scripts/setup_wrapper.py.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

step() { printf " => %s\n" "$*"; }
done_msg() { printf "    ... done\n"; }
fail_msg() { printf "    ... FAILED (%s)\n" "$*" >&2; }

export TZ=Asia/Kuala_Lumpur

echo "=== Corvia Workspace: post-start ==="

# ── 1/5 ───────────────────────────────────────────────────────────────
step "Forwarding host authentication"
forward_host_auth

# ── 2/5 ───────────────────────────────────────────────────────────────
step "corvia health check"
if command -v corvia >/dev/null 2>&1; then
    corvia init --yes || fail_msg "corvia init failed"
else
    fail_msg "corvia not on PATH — run post-create or install manually"
fi

# ── 3/5 ───────────────────────────────────────────────────────────────
step "Starting corvia serve"
if ! corvia serve --help >/dev/null 2>&1; then
    fail_msg "corvia serve not supported by installed binary — skipping"
elif bash -c 'echo > /dev/tcp/127.0.0.1/8020' 2>/dev/null; then
    echo "    already running on port 8020"
else
    nohup corvia serve --port 8020 >> "$WORKSPACE_ROOT/.corvia/serve.log" 2>&1 &
    for i in 1 2 3 4 5; do
        sleep 1
        if bash -c 'echo > /dev/tcp/127.0.0.1/8020' 2>/dev/null; then
            done_msg
            break
        fi
    done
    if ! bash -c 'echo > /dev/tcp/127.0.0.1/8020' 2>/dev/null; then
        fail_msg "not responding after 5s — check .corvia/serve.log"
    fi
fi

# ── 4/5 ───────────────────────────────────────────────────────────────
step "Claude Code integration"
printf "    superpowers plugin: "
install_claude_plugin "https://github.com/obra/superpowers.git" superpowers claude-plugins-official \
    || fail_msg "git clone failed — check network connectivity"

# ── 5/5 ───────────────────────────────────────────────────────────────
# Sweep cargo build artifacts if disk is >70% full.
"$SCRIPT_DIR/sweep-cargo-cache.sh" || true

echo ""
echo "Ready."
