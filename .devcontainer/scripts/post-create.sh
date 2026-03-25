#!/bin/bash
# LEGACY FALLBACK — this script is used only when the `task` binary is unavailable.
# The primary setup orchestration is in .devcontainer/Taskfile.yml, invoked by
# .devcontainer/scripts/setup_wrapper.py. Locking and done-marker are handled
# by setup_wrapper.py (fcntl.flock + boot-id).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

step() { printf " => %s\n" "$*"; }

echo "=== Corvia Workspace: post-create ==="

step "Waiting for network"
wait_for_network || exit 1

# Forward gh auth first — binary download uses gh if available
step "Forwarding GitHub credentials"
forward_gh_auth

step "Installing Corvia binaries"
retry 3 install_binaries

step "Initializing workspace"
init_workspace

step "Setting up hooks (git + doc-placement)"
if command -v corvia >/dev/null 2>&1; then
    corvia workspace init-hooks 2>/dev/null && echo "    hooks initialized" || echo "    hook init deferred (server not ready)"
fi

step "Ensuring tooling"
ensure_tooling

step "Installing VS Code extensions"
EXT_DIR="$WORKSPACE_ROOT/.devcontainer/extensions/corvia-services"
VSIX="$EXT_DIR/corvia-services-$(python3 -c "import json; print(json.load(open('$EXT_DIR/package.json'))['version'])").vsix"
if [ -f "$VSIX" ]; then
    install_vsix_direct "$VSIX"
elif [ -f "$EXT_DIR/package.json" ] && command -v vsce >/dev/null 2>&1; then
    printf "    building extension"
    if (cd "$EXT_DIR" && vsce package --no-dependencies) >/dev/null 2>&1; then
        echo " done"
        VSIX=$(ls -t "$EXT_DIR"/*.vsix 2>/dev/null | head -1)
        [ -n "$VSIX" ] && install_vsix_direct "$VSIX"
    else
        echo " FAILED"
    fi
else
    echo "    no .vsix found — build with: cd $EXT_DIR && vsce package --no-dependencies"
fi

echo ""
echo "=== post-create complete ==="
echo "Run 'corvia-dev status' to see available services."
echo "Run 'corvia-dev use ollama' to switch to Ollama embeddings."
