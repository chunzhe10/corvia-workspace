#!/bin/bash
set -e

echo "=== Corvia Workspace: Post-Create Setup ==="

# Capture workspace root (where devcontainer mounts the workspace)
WORKSPACE_ROOT="$(pwd)"

# Build Corvia from source (repos cloned by workspace init)
echo "Initializing workspace..."
corvia workspace init 2>/dev/null || {
    echo "Corvia not installed — building from source..."
    git clone https://github.com/chunzhe10/corvia repos/corvia 2>/dev/null || true
    cd "$WORKSPACE_ROOT/repos/corvia"
    cargo install --path crates/corvia-cli
    cd "$WORKSPACE_ROOT"
    corvia workspace init
}

# Pull Ollama model
echo "Pulling embedding model..."
ollama serve &
OLLAMA_PID=$!
sleep 3
ollama pull nomic-embed-text
kill $OLLAMA_PID 2>/dev/null || true

echo "=== Post-Create Complete ==="
