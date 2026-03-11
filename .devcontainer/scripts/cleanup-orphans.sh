#!/bin/bash
# TEMPORARY WORKAROUND for Claude Code memory leak via orphaned processes in WSL.
# Upstream issue: https://github.com/anthropics/claude-code/issues
# Remove this script once the upstream fix lands.
#
# Called automatically by Claude Code SessionEnd hook, or manually:
#   bash .devcontainer/scripts/cleanup-orphans.sh
#
# Throttled: only runs once per 10 minutes to avoid redundant work.
# Only targets processes reparented to init (PID 1) — truly orphaned.

set -euo pipefail

QUIET="${1:-}"
log() { [ "$QUIET" = "--quiet" ] || echo "$*"; }

# ── Throttle: skip if we ran less than 10 minutes ago ──────────────
THROTTLE_FILE="/tmp/corvia-cleanup-orphans.last"
THROTTLE_SECONDS=600
if [ -f "$THROTTLE_FILE" ]; then
    last_run=$(cat "$THROTTLE_FILE" 2>/dev/null || echo 0)
    now=$(date +%s)
    elapsed=$((now - last_run))
    if [ "$elapsed" -lt "$THROTTLE_SECONDS" ]; then
        log "cleanup: throttled (ran ${elapsed}s ago, next in $((THROTTLE_SECONDS - elapsed))s)"
        exit 0
    fi
fi
date +%s > "$THROTTLE_FILE"

killed=0

# ── 1. Orphaned node processes from Claude Code (reparented to init) ──
# Only targets node processes whose parent is PID 1 (parent died = orphaned)
# and whose command line contains "claude". Skips anything under 10 minutes
# to avoid killing active subagents.
while IFS= read -r pid; do
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ "$ppid" = "1" ] || continue

    etimes=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -n "$etimes" ] && [ "$etimes" -ge 600 ] || continue

    cmdline=$(ps -o args= -p "$pid" 2>/dev/null || true)
    log "  killing orphaned node process: pid=$pid (uptime=${etimes}s)"
    log "    cmd: ${cmdline:0:120}"
    kill "$pid" 2>/dev/null && killed=$((killed + 1)) || true
done < <(pgrep -f 'node.*claude' 2>/dev/null || true)

# ── 2. Drop filesystem caches under memory pressure (WSL only) ──
# WSL's memory management benefits from explicit cache drops; native Linux does not.
if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
    mem_available=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
    mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 1)
    if [ "$mem_total" -gt 0 ]; then
        pct_available=$((mem_available * 100 / mem_total))
        if [ "$pct_available" -lt 15 ]; then
            log "  memory pressure detected (${pct_available}% available) — dropping caches"
            sync
            echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true
        fi
    fi
fi

if [ "$killed" -gt 0 ]; then
    log "cleaned up $killed orphaned process(es)"
else
    log "no orphaned processes found"
fi
