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
    cargo install --path crates/corvia-inference
    cd "$WORKSPACE_ROOT"
    corvia workspace init
}

# Install corvia-workspace toggle command
chmod +x .devcontainer/scripts/corvia-workspace.sh
ln -sf "$WORKSPACE_ROOT/.devcontainer/scripts/corvia-workspace.sh" /usr/local/bin/corvia-workspace

echo "=== Post-Create Complete ==="
echo "Run 'corvia-workspace status' to see available services."
echo "Run 'corvia-workspace enable ollama' for Ollama embeddings."
echo "Run 'corvia-workspace enable surrealdb' for SurrealDB FullStore."
