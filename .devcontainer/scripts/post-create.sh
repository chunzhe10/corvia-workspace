#!/bin/bash
set -e

echo "=== Corvia Workspace: Post-Create Setup ==="

# Build Corvia from source (repos cloned by workspace init)
echo "Initializing workspace..."
corvia workspace init 2>/dev/null || {
    echo "Corvia not installed — building from source..."
    git clone https://github.com/anthropics/corvia repos/corvia 2>/dev/null || true
    cd /workspace/repos/corvia
    cargo install --path crates/corvia-cli
    cd /workspace
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
