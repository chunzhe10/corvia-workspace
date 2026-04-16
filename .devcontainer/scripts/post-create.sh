#!/bin/bash
# LEGACY FALLBACK — this script is used only when the `task` binary is unavailable.
# The primary setup orchestration is in .devcontainer/Taskfile.yml, invoked by
# .devcontainer/scripts/setup_wrapper.py.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

step() { printf " => %s\n" "$*"; }

echo "=== Corvia Workspace: post-create ==="

step "Waiting for network"
wait_for_network || exit 1

step "Forwarding GitHub credentials"
forward_gh_auth

step "Installing corvia binary"
python3 "$SCRIPT_DIR/install_corvia.py"

step "Initializing corvia"
corvia init --yes

step "Installing VS Code extensions"
EXT_DIR="$WORKSPACE_ROOT/.devcontainer/extensions/corvia-services"
VSIX="$EXT_DIR/corvia-services-$(python3 -c "import json; print(json.load(open('$EXT_DIR/package.json'))['version'])" 2>/dev/null || echo "0.0.0").vsix"
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
