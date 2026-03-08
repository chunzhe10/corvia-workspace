#!/bin/bash
# corvia-supervisor.sh — restarts corvia serve on crash with exponential backoff
# Usage: corvia-supervisor.sh [corvia-args...]
#   e.g. corvia-supervisor.sh serve --mcp

set -uo pipefail

CORVIA_BIN="${CORVIA_BIN:-/usr/local/bin/corvia}"
CORVIA_WORKDIR="${CORVIA_WORKSPACE:-/workspaces/corvia-workspace}"
LOG_FILE="${CORVIA_SUPERVISOR_LOG:-/tmp/corvia-supervisor.log}"
PID_FILE="/tmp/corvia-supervisor.pid"
CHILD_PID_FILE="/tmp/corvia-server.pid"

MAX_BACKOFF=60
RESET_AFTER=300  # reset backoff after 5 min of stable running

log() { echo "$(date -Iseconds) [supervisor] $*" | tee -a "$LOG_FILE"; }

cleanup() {
    log "Supervisor shutting down"
    if [ -f "$CHILD_PID_FILE" ]; then
        local pid
        pid=$(cat "$CHILD_PID_FILE")
        kill "$pid" 2>/dev/null && log "Stopped corvia (pid $pid)"
        rm -f "$CHILD_PID_FILE"
    fi
    rm -f "$PID_FILE"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Write our own PID
echo $$ > "$PID_FILE"

# Ensure we're in the workspace directory (corvia needs corvia.toml)
cd "$CORVIA_WORKDIR" || { log "Cannot cd to $CORVIA_WORKDIR"; exit 1; }

backoff=1

while true; do
    log "Starting: $CORVIA_BIN $*"
    start_time=$(date +%s)

    "$CORVIA_BIN" "$@" &
    child=$!
    echo "$child" > "$CHILD_PID_FILE"
    log "corvia started (pid $child)"

    wait "$child"
    exit_code=$?
    rm -f "$CHILD_PID_FILE"

    elapsed=$(( $(date +%s) - start_time ))

    if [ $exit_code -eq 0 ]; then
        log "corvia exited cleanly (code 0). Not restarting."
        break
    fi

    log "corvia crashed (exit code $exit_code) after ${elapsed}s"

    # Reset backoff if it ran long enough
    if [ "$elapsed" -ge "$RESET_AFTER" ]; then
        backoff=1
    fi

    log "Restarting in ${backoff}s..."
    sleep "$backoff"

    # Exponential backoff capped at MAX_BACKOFF
    backoff=$(( backoff * 2 ))
    if [ "$backoff" -gt "$MAX_BACKOFF" ]; then
        backoff=$MAX_BACKOFF
    fi
done

rm -f "$PID_FILE"
