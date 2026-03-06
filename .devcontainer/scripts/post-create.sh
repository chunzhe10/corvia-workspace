#!/bin/bash
set -euo pipefail

err() { echo "Error: $*" >&2; }

# Print status while a background command runs
# Usage: spin "message" command args...
spin() {
    local msg="$1"; shift
    "$@" >/dev/null 2>&1 &
    local pid=$!
    printf "  %s " "$msg"
    while kill -0 "$pid" 2>/dev/null; do
        printf "."
        sleep 1
    done
    if wait "$pid"; then
        echo " done"
    else
        echo " FAILED"
        return 1
    fi
}

echo "=== Corvia Workspace: Post-Create Setup ==="

WORKSPACE_ROOT="${CORVIA_WORKSPACE:-$(pwd)}"

# Wait for network to be ready before any downloads
printf "  Waiting for network "
for attempt in $(seq 1 30); do
    if curl -fsL --max-time 2 -o /dev/null https://github.com 2>/dev/null; then
        echo " ready"
        break
    fi
    printf "."
    sleep 2
done
if ! curl -fsL --max-time 2 -o /dev/null https://github.com 2>/dev/null; then
    err "Network not available after 60 seconds. Cannot proceed."
    exit 1
fi

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  ARCH_SUFFIX="amd64" ;;
    aarch64) ARCH_SUFFIX="arm64" ;;
    *)       err "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Install Corvia binaries from GitHub release
GH_REPO="chunzhe10/corvia"
INSTALL_DIR="/usr/local/bin"

download_binaries() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local cli_asset="corvia-cli-linux-${ARCH_SUFFIX}"
    local inf_asset="corvia-inference-linux-${ARCH_SUFFIX}"

    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        spin "Downloading binaries (gh)..." \
            gh release download --repo "$GH_REPO" --pattern "$cli_asset" --pattern "$inf_asset" --dir "$tmpdir"
    else
        local url="https://github.com/$GH_REPO/releases/latest/download"
        curl -fsL --retry 3 --retry-delay 2 -o "$tmpdir/$cli_asset" "$url/$cli_asset" 2>/dev/null &
        local pid_cli=$!
        curl -fsL --retry 3 --retry-delay 2 -o "$tmpdir/$inf_asset" "$url/$inf_asset" 2>/dev/null &
        local pid_inf=$!
        printf "  Downloading binaries (curl)... "
        while kill -0 "$pid_cli" 2>/dev/null || kill -0 "$pid_inf" 2>/dev/null; do
            printf "."
            sleep 1
        done
        local ok=true
        wait "$pid_cli" || ok=false
        wait "$pid_inf" || ok=false
        if [ "$ok" = true ]; then
            echo " done"
        else
            echo " FAILED"
            rm -rf "$tmpdir"
            return 1
        fi
    fi

    cp "$tmpdir/$cli_asset" "$INSTALL_DIR/corvia"
    cp "$tmpdir/$inf_asset" "$INSTALL_DIR/corvia-inference"
    chmod +x "$INSTALL_DIR/corvia" "$INSTALL_DIR/corvia-inference"
    rm -rf "$tmpdir"
}

echo "Installing Corvia binaries..."
if ! download_binaries; then
    err "Failed to download binaries."
    err "Ensure 'gh auth login' is done on host, or check network connectivity."
    exit 1
fi

spin "Initializing workspace..." corvia workspace init

# Install corvia-workspace toggle command
chmod +x "$WORKSPACE_ROOT/.devcontainer/scripts/corvia-workspace.sh"
ln -sf "$WORKSPACE_ROOT/.devcontainer/scripts/corvia-workspace.sh" "$INSTALL_DIR/corvia-workspace"

spin "Installing Claude Code CLI..." npm install -g --silent @anthropic-ai/claude-code

echo "=== Post-Create Complete ==="
echo "Run 'corvia-workspace status' to see available services."
echo "Run 'corvia-workspace enable ollama' for Ollama embeddings."
echo "Run 'corvia-workspace enable surrealdb' for SurrealDB FullStore."
echo "Run 'corvia-workspace rebuild' to recompile from local source."
