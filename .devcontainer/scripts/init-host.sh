#!/bin/bash
# Runs on the HOST before the container is created.
# Ensures directories exist so bind mounts don't fail.
set -euo pipefail

HOME_DIR="${HOME:-${USERPROFILE:-}}"
if [ -z "$HOME_DIR" ]; then
    echo "Warning: Cannot determine home directory — auth forwarding may not work"
    exit 0
fi

# Create directories if they don't exist so Docker bind mounts succeed.
# These are no-ops if the directories already exist.
mkdir -p "$HOME_DIR/.config/gh"
mkdir -p "$HOME_DIR/.claude"

echo "Host auth directories verified."
