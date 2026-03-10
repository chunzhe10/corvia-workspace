#!/bin/bash
# Shared functions for devcontainer scripts.
# Source this file; do not execute directly.

err() { echo "Error: $*" >&2; }

# Retry a command up to N times with exponential backoff.
# Usage: retry <max_attempts> command args...
retry() {
    local max="$1"; shift
    local attempt=1 delay=5
    while true; do
        if "$@"; then
            return 0
        fi
        if [ "$attempt" -ge "$max" ]; then
            err "Failed after $max attempts: $*"
            return 1
        fi
        echo "  Attempt $attempt/$max failed, retrying in ${delay}s..."
        sleep "$delay"
        attempt=$((attempt + 1))
        delay=$((delay * 2))
    done
}

# Print status while a background command runs.
# Usage: spin "message" command args...
# On failure, shows captured output for debugging.
spin() {
    local msg="$1"; shift
    local logfile
    logfile=$(mktemp)
    "$@" >"$logfile" 2>&1 &
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
        if [ -s "$logfile" ]; then
            echo "--- output from: $* ---" >&2
            cat "$logfile" >&2
            echo "--- end output ---" >&2
        fi
        rm -f "$logfile"
        return 1
    fi
    rm -f "$logfile"
}

WORKSPACE_ROOT="${CORVIA_WORKSPACE:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect architecture suffix for binary downloads.
detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *)       err "Unsupported architecture: $arch"; return 1 ;;
    esac
}

# Wait for network connectivity (up to 60s).
wait_for_network() {
    printf "  Waiting for network "
    for _attempt in $(seq 1 30); do
        if curl -fsL --max-time 2 -o /dev/null https://github.com 2>/dev/null; then
            echo " ready"
            return 0
        fi
        printf "."
        sleep 2
    done
    if ! curl -fsL --max-time 2 -o /dev/null https://github.com 2>/dev/null; then
        err "Network not available after 60 seconds."
        return 1
    fi
}

# Download and install corvia + corvia-inference binaries.
install_binaries() {
    local arch_suffix
    arch_suffix="$(detect_arch)" || return 1
    local gh_repo="chunzhe10/corvia"
    local install_dir="/usr/local/bin"
    local tmpdir
    tmpdir=$(mktemp -d)
    local cli_asset="corvia-cli-linux-${arch_suffix}"
    local inf_asset="corvia-inference-linux-${arch_suffix}"

    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        spin "Downloading binaries (gh)..." \
            gh release download --repo "$gh_repo" --pattern "$cli_asset" --pattern "$inf_asset" --dir "$tmpdir"
    else
        local url="https://github.com/$gh_repo/releases/latest/download"
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

    sudo cp "$tmpdir/$cli_asset" "$install_dir/corvia"
    sudo cp "$tmpdir/$inf_asset" "$install_dir/corvia-inference"
    sudo chmod +x "$install_dir/corvia" "$install_dir/corvia-inference"
    rm -rf "$tmpdir"
}

# Download the latest VS Code extension VSIX from workspace releases.
install_extension() {
    local gh_repo="chunzhe10/corvia-workspace"
    local ext_dir="$WORKSPACE_ROOT/.devcontainer/extensions/corvia-services"
    local tmpdir
    tmpdir=$(mktemp -d)

    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        gh release download --repo "$gh_repo" --pattern "corvia-services-*.vsix" --dir "$tmpdir" 2>/dev/null || return 1
    else
        local url="https://github.com/$gh_repo/releases/latest/download"
        # Try to fetch the asset list; fall back to known name
        curl -fsL --retry 3 --retry-delay 2 -o "$tmpdir/corvia-services.vsix" \
            "$url/corvia-services-0.2.0.vsix" 2>/dev/null || return 1
    fi

    # Install the newest VSIX found
    local vsix
    vsix=$(ls -t "$tmpdir"/corvia-services-*.vsix "$tmpdir"/corvia-services.vsix 2>/dev/null | head -1)
    if [ -n "$vsix" ] && [ -f "$vsix" ]; then
        mkdir -p "$ext_dir"
        cp "$vsix" "$ext_dir/"
        echo "  Downloaded extension: $(basename "$vsix")"
    fi
    rm -rf "$tmpdir"
}

# Ensure corvia binary is available, installing if needed.
ensure_corvia() {
    if [ -x "/usr/local/bin/corvia" ]; then
        return 0
    fi
    echo "corvia binary not found — installing..."
    wait_for_network || return 1
    echo "Installing Corvia binaries..."
    retry 3 install_binaries
}

# Fix ownership of workspace files so the current user can write.
# Needed when workspace is mounted/cloned as root but scripts run as vscode.
# Uses find to only chown files not already owned by the current user,
# avoiding a slow recursive chown on every start.
fix_workspace_perms() {
    local uid
    uid="$(id -u)"
    if find "$WORKSPACE_ROOT" -maxdepth 1 -not -user "$uid" -print -quit 2>/dev/null | grep -q .; then
        echo "  Fixing workspace permissions..."
        sudo chown -R "$uid:$(id -g)" "$WORKSPACE_ROOT"
    fi
}

# Initialize the corvia workspace.
init_workspace() {
    fix_workspace_perms
    spin "Initializing workspace..." corvia workspace init
}

# Install a Python package in editable mode using uv (preferred) or pip.
# Uses sudo because /usr/local/lib/python3.x/ is root-owned.
install_python_editable() {
    local pkg_path="$1"
    if command -v uv >/dev/null 2>&1; then
        sudo uv pip install --system --break-system-packages -e "$pkg_path" --quiet
    elif command -v pip3 >/dev/null 2>&1 || python3 -m pip --version >/dev/null 2>&1; then
        sudo python3 -m pip install -e "$pkg_path" --quiet --break-system-packages
    else
        err "Neither uv nor pip available. Install uv: curl -LsSf https://astral.sh/uv/install.sh | sh"
        return 1
    fi
}

# Ensure uv is installed and available to sudo.
ensure_uv() {
    # Need uv in /usr/local/bin so sudo can find it
    if [ -x /usr/local/bin/uv ]; then
        return 0
    fi
    echo "uv not found in /usr/local/bin — installing..."
    curl -LsSf --retry 5 --retry-delay 3 https://astral.sh/uv/install.sh | sh
    # uv installer puts it in ~/.local/bin; copy to global path
    local src="${HOME}/.local/bin/uv"
    if [ -f "$src" ]; then
        sudo cp "$src" /usr/local/bin/uv
        sudo cp "${HOME}/.local/bin/uvx" /usr/local/bin/uvx 2>/dev/null || true
    fi
    [ -x /usr/local/bin/uv ]
}

# Ensure all tooling is installed (catches up if post-create was incomplete).
ensure_tooling() {
    ensure_corvia
    ensure_uv

    if ! command -v corvia-dev >/dev/null 2>&1; then
        echo "corvia-dev not found — installing..."
        retry 3 install_python_editable "$WORKSPACE_ROOT/tools/corvia-dev"
    fi

    if ! command -v claude >/dev/null 2>&1; then
        echo "Claude Code not found — installing..."
        retry 3 spin "Installing Claude Code CLI..." sudo npm install -g --silent @anthropic-ai/claude-code
    fi
}
