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

echo ""
echo "=== post-create complete ==="
