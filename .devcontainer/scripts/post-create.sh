#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Prevent duplicate runs when multiple VS Code clients connect simultaneously.
LOCK_FILE="/tmp/corvia-post-create.lock"
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
    echo "post-create.sh is already running (lock: $LOCK_FILE). Skipping."
    exit 0
fi
trap 'rmdir "$LOCK_FILE" 2>/dev/null' EXIT

echo "=== Corvia Workspace: Post-Create Setup ==="

wait_for_network || exit 1

echo "Installing Corvia binaries..."
retry 3 install_binaries

init_workspace

ensure_tooling

echo "=== Post-Create Complete ==="
echo "Run 'corvia-dev status' to see available services."
echo "Run 'corvia-dev use ollama' to switch to Ollama embeddings."
echo "Run 'corvia-dev enable coding-llm' to enable local coding LLM."
echo "Run 'corvia-dev enable surrealdb' to enable SurrealDB FullStore."
