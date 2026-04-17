#!/bin/bash
# Shared functions for devcontainer scripts.
# Source this file; do not execute directly.

err() { echo "Error: $*" >&2; }

# Colored [module] log output. Usage: log <module> <message>
# Colors: infra=cyan, core=green, ide=magenta, warn=yellow
log() {
    local mod="$1"; shift
    printf '\033[36m[%s]\033[0m %s\n' "$mod" "$*"
}
logg() {
    local mod="$1"; shift
    printf '\033[32m[%s]\033[0m %s\n' "$mod" "$*"
}
logm() {
    local mod="$1"; shift
    printf '\033[35m[%s]\033[0m %s\n' "$mod" "$*"
}
logw() {
    local mod="$1"; shift
    printf '\033[33m[%s]\033[0m %s\n' "$mod" "$*"
}

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

# Detect if running inside WSL.
is_wsl() {
    grep -qi "microsoft\|wsl" /proc/version 2>/dev/null
}

# Detect if GPU (NVIDIA) is available inside the container.
has_gpu() {
    command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1
}

WORKSPACE_ROOT="${CORVIA_WORKSPACE:-$(pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

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

# Forward GitHub CLI credentials from host mount.
# Copies host config into the container's ~/.config/gh if the host has valid auth
# and the container doesn't, or if the host config is newer.
forward_gh_auth() {
    local host_dir="/root/.config/gh-host"
    local local_dir="/root/.config/gh"
    local host_hosts="$host_dir/hosts.yml"
    local local_hosts="$local_dir/hosts.yml"

    if [ ! -d "$host_dir" ] || [ ! -f "$host_hosts" ]; then
        logw auth "gh: no host credentials (run 'gh auth login' on host)"
        return 0
    fi
    if [ ! -s "$host_hosts" ]; then
        logw auth "gh: host credentials empty"
        return 0
    fi
    if ! grep -q "oauth_token:" "$host_hosts" 2>/dev/null; then
        logw auth "gh: token in system keyring — rebuild container or 'gh auth login' inside"
        return 0
    fi

    if [ ! -f "$local_hosts" ] || [ "$host_hosts" -nt "$local_hosts" ]; then
        mkdir -p "$local_dir"
        cp "$host_hosts" "$local_hosts"
        [ -f "$host_dir/config.yml" ] && cp "$host_dir/config.yml" "$local_dir/config.yml"
        log auth "gh: forwarded from host"
    else
        log auth "gh: up to date"
    fi

    local auth_ok=false
    for _gh_attempt in 1 2 3; do
        if gh auth status >/dev/null 2>&1; then
            auth_ok=true
            break
        fi
        if [ "$_gh_attempt" -lt 3 ]; then
            logw auth "gh: auth check failed, retrying (${_gh_attempt}/3)..."
            sleep 2
            cp "$host_hosts" "$local_hosts"
        fi
    done
    if [ "$auth_ok" = true ]; then
        local gh_user
        gh_user=$(gh api user --jq .login 2>/dev/null || echo "unknown")
        log auth "gh: authenticated as $gh_user"
    else
        err "gh: forwarded credentials invalid — run 'gh auth login'"
    fi
}

# Ensure Claude Code credentials are available.
# Primary: direct bind mount of ~/.claude (read-write, tokens can refresh).
# Fallback: copy from read-only .claude-host mount if direct mount failed.
# Last resort: prompt user to authenticate manually.
forward_claude_auth() {
    local creds="/root/.claude/.credentials.json"

    if [ -f "$creds" ] && python3 -c "import json; json.load(open('$creds'))" 2>/dev/null; then
        log auth "claude: credentials available"
        return 0
    fi

    local host_creds="/root/.claude-host/.credentials.json"
    if [ -f "$host_creds" ] && python3 -c "import json; json.load(open('$host_creds'))" 2>/dev/null; then
        mkdir -p /root/.claude
        cp "$host_creds" /root/.claude/.credentials.json
        [ -f "/root/.claude-host/settings.json" ] && cp "/root/.claude-host/settings.json" /root/.claude/settings.json
        log auth "claude: forwarded from host"
        return 0
    fi

    logw auth "claude: no credentials — run 'claude' to authenticate"
}

# Forward all host authentication into the container.
# Safe to call multiple times — only copies when host is newer or local is missing.
forward_host_auth() {
    forward_gh_auth
    forward_claude_auth
}

# Install a Claude Code plugin directly via git clone, bypassing the claude CLI.
# Usage: install_claude_plugin <git_repo_url> <plugin_name> <marketplace_name>
# Example: install_claude_plugin https://github.com/obra/superpowers.git superpowers claude-plugins-official
install_claude_plugin() {
    local repo_url="$1"
    local plugin_name="$2"
    local marketplace="${3:-claude-plugins-official}"
    local plugin_key="${plugin_name}@${marketplace}"

    local plugins_json="/root/.claude/plugins/installed_plugins.json"
    local cache_base="/root/.claude/plugins/cache/${marketplace}/${plugin_name}"

    # Ensure workspace symlink so AI file search can find plugin skills.
    # The plugin runtime injects skills via JS hook, but Claude (the AI model)
    # also needs to read SKILL.md files during conversations — and it searches
    # the workspace tree, not ~/.claude/plugins/cache/.
    _link_plugin_skills() {
        local target_skills="$1/skills"
        local link_path="${WORKSPACE_ROOT}/.agents/skills/${plugin_name}"
        if [ -d "$target_skills" ]; then
            mkdir -p "$(dirname "$link_path")"
            ln -sfn "$target_skills" "$link_path"
            logm claude "${plugin_name}: linked skills → ${link_path}"
        fi
    }

    # Check if already installed by looking at installed_plugins.json
    if [ -f "$plugins_json" ] && python3 -c "
import json, sys
d = json.load(open('$plugins_json'))
entries = d.get('plugins', {}).get('$plugin_key', [])
if entries and entries[0].get('installPath'):
    import os
    sys.exit(0 if os.path.isdir(entries[0]['installPath']) else 1)
sys.exit(1)
" 2>/dev/null; then
        # Plugin exists — still ensure the workspace symlink is current
        local existing_path
        existing_path=$(python3 -c "
import json
d = json.load(open('$plugins_json'))
print(d['plugins']['$plugin_key'][0]['installPath'])
" 2>/dev/null)
        [ -n "$existing_path" ] && _link_plugin_skills "$existing_path"
        logm claude "${plugin_name}: already installed"
        return 0
    fi

    # Clone the repo
    local tmpdir
    tmpdir=$(mktemp -d)
    if ! git clone --depth 1 "$repo_url" "$tmpdir" 2>/dev/null; then
        rm -rf "$tmpdir"
        return 1
    fi

    # Detect version: check git tags, then default to "1.0.0"
    local version sha
    sha=$(git -C "$tmpdir" rev-parse HEAD 2>/dev/null || echo "unknown")
    version=$(git -C "$tmpdir" describe --tags --exact-match HEAD 2>/dev/null || true)
    # Strip leading 'v' from version tags
    version="${version#v}"
    if [ -z "$version" ]; then
        version="1.0.0"
    fi

    local install_path="${cache_base}/${version}"
    mkdir -p "$(dirname "$install_path")"

    # Move the clone into the cache (preserves .git for future updates)
    rm -rf "$install_path"
    mv "$tmpdir" "$install_path"

    # Register in installed_plugins.json
    local now
    now=$(python3 -c "from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z'))")
    mkdir -p "$(dirname "$plugins_json")"
    python3 -c "
import json, os
path = '$plugins_json'
d = json.load(open(path)) if os.path.exists(path) else {'version': 2, 'plugins': {}}
d['plugins']['$plugin_key'] = [{
    'scope': 'user',
    'installPath': '$install_path',
    'version': '$version',
    'installedAt': '$now',
    'lastUpdated': '$now',
    'gitCommitSha': '$sha'
}]
json.dump(d, open(path, 'w'), indent=2)
"
    _link_plugin_skills "$install_path"
    logm claude "superpowers: installed v${version}"
}
