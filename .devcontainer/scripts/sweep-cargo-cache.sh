#!/bin/bash
# Sweep cargo build artifacts to prevent disk exhaustion.
# Triggered by: Claude Code SessionStart hook, container post-start.sh, manual.
# Safe to call anytime -- skips if disk is under threshold or build is running.
set -euo pipefail

TARGET_DIR="/workspaces/corvia-workspace/repos/corvia/target"
[ -d "$TARGET_DIR" ] || exit 0

# Skip if build in progress
if pgrep -f "cargo build\|cargo check\|cargo test\|rustc" >/dev/null 2>&1; then
    echo "$(date -Iseconds) sweep: build in progress, skipping"
    exit 0
fi

USED_PCT=$(df --output=pcent / | tail -1 | tr -d ' %')

if [ "$USED_PCT" -ge 90 ]; then
    # Emergency: nuke everything, cargo will rebuild
    echo "$(date -Iseconds) sweep: EMERGENCY cleanup (${USED_PCT}% used)"
    BEFORE=$(du -sm "$TARGET_DIR" 2>/dev/null | cut -f1)
    rm -rf "$TARGET_DIR/debug/incremental"
    rm -rf "$TARGET_DIR/debug/deps"
    rm -rf "$TARGET_DIR/debug/build"
    AFTER=$(du -sm "$TARGET_DIR" 2>/dev/null | cut -f1)
    echo "  freed $((BEFORE - AFTER))MB (target was ${BEFORE}MB, now ${AFTER}MB)"

elif [ "$USED_PCT" -ge 70 ]; then
    # Routine: nuke incremental, prune old deps
    echo "$(date -Iseconds) sweep: routine cleanup (${USED_PCT}% used)"
    BEFORE=$(du -sm "$TARGET_DIR" 2>/dev/null | cut -f1)

    # 1. Nuke incremental cache (10-15GB, rebuilt on next compile)
    rm -rf "$TARGET_DIR/debug/incremental"

    # 2. Remove old dep artifacts (>2 days). Preserve .d files so cargo
    #    can detect staleness cleanly on next build.
    find "$TARGET_DIR/debug/deps" -type f -mtime +2 ! -name "*.d" -delete 2>/dev/null || true

    # 3. Remove old build script outputs (>2 days)
    find "$TARGET_DIR/debug/build" -maxdepth 1 -type d -mtime +2 -exec rm -rf {} + 2>/dev/null || true

    AFTER=$(du -sm "$TARGET_DIR" 2>/dev/null | cut -f1)
    echo "  freed $((BEFORE - AFTER))MB (target was ${BEFORE}MB, now ${AFTER}MB)"
else
    echo "$(date -Iseconds) sweep: disk at ${USED_PCT}% -- skip"
fi
