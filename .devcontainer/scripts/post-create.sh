#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

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
