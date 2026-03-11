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

# Detect platform for informational purposes.
if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
    echo "Platform: WSL"
elif [ "$(uname -s)" = "Linux" ]; then
    echo "Platform: native Linux"
else
    echo "Platform: $(uname -s)"
fi

# Check GPU availability and advise on --gpus flag.
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    echo "GPU: detected — add '\"runArgs\": [\"--gpus\", \"all\"]' to devcontainer.json for GPU passthrough"
else
    echo "GPU: not detected (ok — GPU is optional)"
fi

echo "Host init complete."
