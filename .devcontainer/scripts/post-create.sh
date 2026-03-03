#!/bin/bash
set -e

echo "=== Corvia Workspace: Post-Create Setup ==="

# Capture workspace root (where devcontainer mounts the workspace)
WORKSPACE_ROOT="$(pwd)"

# Install Corvia binaries (prebuilt from GitHub release, or build from source)
RELEASE_URL="https://github.com/chunzhe10/corvia/releases/latest/download"

echo "Downloading prebuilt binaries..."
if curl -fsSL -o /usr/local/bin/corvia "$RELEASE_URL/corvia-cli-linux-amd64" && \
   curl -fsSL -o /usr/local/bin/corvia-inference "$RELEASE_URL/corvia-inference-linux-amd64"; then
    chmod +x /usr/local/bin/corvia /usr/local/bin/corvia-inference
    echo "  Binaries installed from latest release."
else
    echo "  Download failed — building from source..."
    git clone https://github.com/chunzhe10/corvia repos/corvia 2>/dev/null || true
    cd "$WORKSPACE_ROOT/repos/corvia"
    cargo install --path crates/corvia-cli
    cargo install --path crates/corvia-inference
    cd "$WORKSPACE_ROOT"
fi

# Initialize workspace
echo "Initializing workspace..."
corvia workspace init

# Install corvia-workspace toggle command
chmod +x .devcontainer/scripts/corvia-workspace.sh
ln -sf "$WORKSPACE_ROOT/.devcontainer/scripts/corvia-workspace.sh" /usr/local/bin/corvia-workspace

echo "=== Post-Create Complete ==="
echo "Run 'corvia-workspace status' to see available services."
echo "Run 'corvia-workspace enable ollama' for Ollama embeddings."
echo "Run 'corvia-workspace enable surrealdb' for SurrealDB FullStore."
echo "Run 'corvia-workspace rebuild' to recompile from local source."
