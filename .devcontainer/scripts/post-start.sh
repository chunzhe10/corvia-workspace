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
step "Claude Code integration"
printf "    superpowers plugin: "
install_claude_plugin "https://github.com/obra/superpowers.git" superpowers claude-plugins-official \
    || fail_msg "git clone failed — check network connectivity"

# ── 4/5 ───────────────────────────────────────────────────────────────
# Sweep cargo build artifacts if disk is >70% full.
"$SCRIPT_DIR/sweep-cargo-cache.sh" || true

# ── 5/5 ───────────────────────────────────────────────────────────────
# corvia-serve runs last: hard-failure on missing `serve` must not skip
# the steps above (superpowers install, cache sweep).
step "Starting corvia serve"
if ! corvia serve --help >/dev/null 2>&1; then
    _tag="$(cat /usr/local/share/corvia-release-tag 2>/dev/null || true)"
    fail_msg "corvia serve: not supported by installed binary (tag=${_tag:-unknown})"
    fail_msg "this workspace requires a serve-capable binary (corvia >= v1.0.1)"
    fail_msg "remediation: python3 .devcontainer/scripts/install_corvia.py  (or rebuild devcontainer)"
    exit 1
elif curl -sf --max-time 2 http://127.0.0.1:8020/healthz >/dev/null 2>&1; then
    echo "    already running on port 8020"
else
    # Rotate log: keep one previous boot for post-mortem.
    if [ -f "$WORKSPACE_ROOT/.corvia/serve.log" ]; then
        mv -f "$WORKSPACE_ROOT/.corvia/serve.log" "$WORKSPACE_ROOT/.corvia/serve.log.prev"
    fi
    nohup corvia serve --port 8020 > "$WORKSPACE_ROOT/.corvia/serve.log" 2>&1 &
    _ready=0
    # 30s budget accommodates first-boot embedder download (~17s observed).
    for i in $(seq 1 30); do
        sleep 1
        if curl -sf --max-time 2 http://127.0.0.1:8020/healthz >/dev/null 2>&1; then
            echo "    ready (${i}s)"
            _ready=1
            break
        fi
    done
    if [ "$_ready" -eq 0 ]; then
        fail_msg "corvia serve: /healthz not responding after 30s — check .corvia/serve.log"
        exit 1
    fi
fi

echo ""
echo "Ready."
