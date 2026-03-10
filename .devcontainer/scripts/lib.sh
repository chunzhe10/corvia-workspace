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
# Fallback for when vsce is unavailable to build from source.
install_extension() {
    local gh_repo="chunzhe10/corvia-workspace"
    local ext_dir="$WORKSPACE_ROOT/.devcontainer/extensions/corvia-services"
    local tmpdir
    tmpdir=$(mktemp -d)

    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        gh release download --repo "$gh_repo" --pattern "corvia-services-*.vsix" --dir "$tmpdir" 2>/dev/null || { rm -rf "$tmpdir"; return 1; }
    else
        # List release assets via GitHub API, download the first VSIX match
        local url="https://api.github.com/repos/$gh_repo/releases/latest"
        local asset_url
        asset_url=$(curl -fsL "$url" 2>/dev/null \
            | python3 -c "import sys,json; assets=json.load(sys.stdin).get('assets',[]); vsix=[a for a in assets if a['name'].endswith('.vsix')]; print(vsix[0]['browser_download_url'] if vsix else '')" 2>/dev/null)
        if [ -z "$asset_url" ]; then
            rm -rf "$tmpdir"
            return 1
        fi
        curl -fsL --retry 3 --retry-delay 2 -o "$tmpdir/corvia-services.vsix" "$asset_url" 2>/dev/null \
            || { rm -rf "$tmpdir"; return 1; }
    fi

    local vsix
    vsix=$(ls -t "$tmpdir"/*.vsix 2>/dev/null | head -1)
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

# Ensure gh CLI is installed.
ensure_gh() {
    if command -v gh >/dev/null 2>&1; then
        return 0
    fi
    echo "gh CLI not found — installing..."
    local keyring="/usr/share/keyrings/githubcli-archive-keyring.gpg"
    sudo curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o "$keyring"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=$keyring] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    retry 3 sudo apt-get update
    retry 3 sudo apt-get install -y --no-install-recommends gh
}

# Forward GitHub CLI credentials from host mount.
# Copies host config into the container's ~/.config/gh if the host has valid auth
# and the container doesn't, or if the host config is newer.
forward_gh_auth() {
    local host_dir="/root/.config/gh-host"
    local local_dir="/root/.config/gh"
    local host_hosts="$host_dir/hosts.yml"
    local local_hosts="$local_dir/hosts.yml"

    # No host mount or empty — nothing to forward
    if [ ! -d "$host_dir" ] || [ ! -f "$host_hosts" ]; then
        echo "  gh: no host credentials found (run 'gh auth login' on your host machine)"
        return 0
    fi

    # Validate host config has actual content (not just an empty file)
    if [ ! -s "$host_hosts" ]; then
        echo "  gh: host credentials file is empty — skipping"
        return 0
    fi

    # Copy if container has no auth, or host is newer
    if [ ! -f "$local_hosts" ] || [ "$host_hosts" -nt "$local_hosts" ]; then
        mkdir -p "$local_dir"
        cp "$host_hosts" "$local_hosts"
        # Also copy config.yml if present (protocol preferences, etc.)
        [ -f "$host_dir/config.yml" ] && cp "$host_dir/config.yml" "$local_dir/config.yml"
        echo "  gh: forwarded credentials from host"
    else
        echo "  gh: credentials already up to date"
    fi

    # Verify auth works
    if gh auth status >/dev/null 2>&1; then
        local gh_user
        gh_user=$(gh api user --jq .login 2>/dev/null || echo "unknown")
        echo "  gh: authenticated as $gh_user"
    else
        err "gh: forwarded credentials are invalid — run 'gh auth login' to re-authenticate"
    fi
}

# Forward Claude Code credentials from host mount.
# Copies .credentials.json from the read-only host mount into the container's
# ~/.claude/ if the host has valid credentials and the container doesn't, or if
# the host credentials are newer (e.g. after an OAuth token refresh).
forward_claude_auth() {
    local host_creds="/root/.claude-host/.credentials.json"
    local local_creds="/root/.claude/.credentials.json"

    # No host mount or no credentials file — nothing to forward
    if [ ! -d "/root/.claude-host" ] || [ ! -f "$host_creds" ]; then
        echo "  claude: no host credentials found (run 'claude' on your host machine to authenticate)"
        return 0
    fi

    # Validate host credentials file has actual JSON content
    if [ ! -s "$host_creds" ]; then
        echo "  claude: host credentials file is empty — skipping"
        return 0
    fi
    if ! python3 -c "import json; json.load(open('$host_creds'))" 2>/dev/null; then
        echo "  claude: host credentials file is not valid JSON — skipping"
        return 0
    fi

    # Copy if container has no credentials, or host file is newer (token refresh)
    if [ ! -f "$local_creds" ] || [ "$host_creds" -nt "$local_creds" ]; then
        mkdir -p /root/.claude
        cp "$host_creds" "$local_creds"
        echo "  claude: forwarded credentials from host"
    else
        echo "  claude: credentials already up to date"
    fi

    # Also forward settings.json if it exists and local one doesn't
    local host_settings="/root/.claude-host/settings.json"
    local local_settings="/root/.claude/settings.json"
    if [ -f "$host_settings" ] && [ -s "$host_settings" ] && [ ! -f "$local_settings" ]; then
        cp "$host_settings" "$local_settings"
        echo "  claude: forwarded settings from host"
    fi
}

# Forward all host authentication into the container.
# Safe to call multiple times — only copies when host is newer or local is missing.
forward_host_auth() {
    echo "Forwarding host authentication..."
    forward_gh_auth
    forward_claude_auth
}

# Ensure all tooling is installed (catches up if post-create was incomplete).
ensure_tooling() {
    ensure_corvia
    ensure_uv
    ensure_gh

    if ! command -v corvia-dev >/dev/null 2>&1; then
        echo "corvia-dev not found — installing..."
        retry 3 install_python_editable "$WORKSPACE_ROOT/tools/corvia-dev"
    fi

    if ! command -v claude >/dev/null 2>&1; then
        echo "Claude Code not found — installing..."
        retry 3 spin "Installing Claude Code CLI..." sudo npm install -g --silent @anthropic-ai/claude-code
    fi
}
