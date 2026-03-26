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

# Ensure uv/uvx are on PATH even if the Dockerfile mv to /usr/local/bin failed.
if [ -d "/root/.local/bin" ] && ! echo "$PATH" | grep -q "/root/.local/bin"; then
    export PATH="/root/.local/bin:$PATH"
fi

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

# Ensure corvia_dev Python package is importable.
# Installs it on-demand if missing (e.g., fresh container before ensure_tooling).
_ensure_corvia_dev() {
    if python3 -c "import corvia_dev" 2>/dev/null; then
        return 0
    fi
    logg install "installing corvia-dev..."
    install_python_editable "$WORKSPACE_ROOT/tools/corvia-dev" 2>/dev/null
}

# Download and install corvia release binaries.
# Delegates to Python (corvia_dev.rebuild) which is the single source of truth
# for binary names, paths, versioning, and download logic.
install_binaries() {
    _ensure_corvia_dev || { err "corvia_dev install failed"; return 1; }
    python3 << 'PYEOF' || return 1
import sys
from corvia_dev.rebuild import download_release, get_latest_release_tag
tag = get_latest_release_tag()
if tag:
    print(f"\033[32m[install]\033[0m downloading {tag}...")
installed = download_release(tag=tag)
if not installed:
    print("\033[32m[install]\033[0m FAILED", file=sys.stderr)
    sys.exit(1)
print(f"\033[32m[install]\033[0m done: {', '.join(installed)}")
PYEOF
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

# Install a local VS Code extension by extracting a .vsix into the extensions dir.
# This bypasses the code CLI entirely — works before VS Code's IPC socket is ready.
# Usage: install_vsix_direct <vsix_path>
install_vsix_direct() {
    local vsix_path="$1"
    if [ ! -f "$vsix_path" ]; then
        err "VSIX not found: $vsix_path"
        return 1
    fi

    # Read publisher and name/version from package.json inside the .vsix (it's a zip)
    local pkg_json
    pkg_json=$(VSIX_PATH="$vsix_path" python3 -c "
import zipfile, json, sys, os
with zipfile.ZipFile(os.environ['VSIX_PATH']) as z:
    with z.open('extension/package.json') as f:
        d = json.load(f)
        print(json.dumps({'publisher': d['publisher'], 'name': d['name'], 'version': d['version']}))
" 2>/dev/null) || { err "Failed to read package.json from VSIX"; return 1; }

    local publisher name version
    publisher=$(echo "$pkg_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['publisher'])")
    name=$(echo "$pkg_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
    version=$(echo "$pkg_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])")

    local ext_id="${publisher}.${name}-${version}"

    # Detect VS Code server variant: insiders vs stable
    local server_dirs=()
    if [ -d "/root/.vscode-server-insiders" ]; then
        server_dirs+=("/root/.vscode-server-insiders/extensions")
    fi
    if [ -d "/root/.vscode-server" ]; then
        server_dirs+=("/root/.vscode-server/extensions")
    fi
    # Fallback if neither exists yet (pre-first-connection)
    if [ ${#server_dirs[@]} -eq 0 ]; then
        server_dirs=("/root/.vscode-server/extensions")
    fi

    local installed=0
    for ext_parent in "${server_dirs[@]}"; do
        local ext_dir="${ext_parent}/${ext_id}"

        if [ -d "$ext_dir" ] && [ -f "$ext_dir/package.json" ]; then
            logm vscode "extension: $ext_id already installed"
            installed=1
            continue
        fi

        # Extract extension/ contents from the .vsix into the target directory
        local tmpdir
        tmpdir=$(mktemp -d)
        VSIX_PATH="$vsix_path" EXTRACT_DIR="$tmpdir" python3 -c "
import zipfile, os
with zipfile.ZipFile(os.environ['VSIX_PATH']) as z:
    for info in z.infolist():
        if info.filename.startswith('extension/'):
            # Strip 'extension/' prefix
            rel = info.filename[len('extension/'):]
            if not rel:
                continue
            target = os.path.join(os.environ['EXTRACT_DIR'], rel)
            if info.is_dir():
                os.makedirs(target, exist_ok=True)
            else:
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with z.open(info) as src, open(target, 'wb') as dst:
                    dst.write(src.read())
" 2>/dev/null || { rm -rf "$tmpdir"; err "Failed to extract VSIX"; return 1; }

        mkdir -p "$ext_parent"
        rm -rf "$ext_dir"
        mv "$tmpdir" "$ext_dir"
        logm vscode "extension: installed $ext_id"
        installed=1
    done

    [ "$installed" -eq 1 ] || { err "No VS Code server directory found"; return 1; }
}

# Ensure corvia binaries are installed and up to date.
# Delegates to Python (corvia_dev.rebuild.ensure_up_to_date) which handles
# tag checking, network detection, download, and offline fallback.
ensure_corvia() {
    _ensure_corvia_dev || { err "corvia_dev install failed"; return 1; }
    local result
    result=$(python3 -c "from corvia_dev.rebuild import ensure_up_to_date; print(ensure_up_to_date())" 2>/dev/null) || true

    local tag
    tag=$(cat /usr/local/share/corvia-release-tag 2>/dev/null || echo "unknown")

    case "$result" in
        up_to_date) logg tooling "binaries: up to date ($tag)" ;;
        updated)    logg tooling "binaries: updated to $tag" ;;
        offline_ok) logw tooling "binaries: no network, using existing" ;;
        missing)
            err "binaries missing and no network available"
            return 1
            ;;
        *)
            if [ -x "/usr/local/bin/corvia" ]; then
                logw tooling "binaries: using existing (update check unavailable)"
            else
                err "binaries missing and update check failed"
                return 1
            fi
            ;;
    esac
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

# Clone a repo into a directory that may already contain subdirectories
# (e.g. from Docker volume mounts). Falls back to git init + pull when
# the target directory is non-empty.
# Usage: clone_into_nonempty <url> <dest>
clone_into_nonempty() {
    local url="$1" dest="$2"
    if [ -d "$dest/.git" ]; then
        return 0  # already cloned
    fi
    if [ ! -d "$dest" ] || [ -z "$(ls -A "$dest" 2>/dev/null)" ]; then
        git clone "$url" "$dest"
    else
        # Directory exists and is non-empty (e.g. Docker volume mount created it).
        # Clone to temp, then move .git in and checkout.
        local tmpdir
        tmpdir=$(mktemp -d)
        git clone "$url" "$tmpdir"
        mv "$tmpdir/.git" "$dest/.git"
        rm -rf "$tmpdir"
        git -C "$dest" checkout -- .
    fi
}

# Pre-clone repos listed in corvia.toml before `corvia workspace init`,
# which fails if the target directory is non-empty.
pre_clone_repos() {
    local repos_dir="$WORKSPACE_ROOT/repos"
    # Parse repos from corvia.toml
    python3 -c "
import tomllib, json, sys
with open('$WORKSPACE_ROOT/corvia.toml', 'rb') as f:
    cfg = tomllib.load(f)
for r in cfg.get('workspace', {}).get('repos', []):
    print(json.dumps({'name': r['name'], 'url': r['url']}))
" 2>/dev/null | while IFS= read -r line; do
        local name url dest
        name=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
        url=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin)['url'])")
        dest="$repos_dir/$name"
        if [ ! -d "$dest/.git" ]; then
            echo "  Cloning $name..."
            clone_into_nonempty "$url" "$dest" || err "Failed to clone $name"
        fi
    done
}

# Initialize the corvia workspace.
init_workspace() {
    fix_workspace_perms
    pre_clone_repos
    (cd "$WORKSPACE_ROOT" && spin "Initializing workspace..." corvia workspace init)
}

# Install a Python package in editable mode using uv.
# Uses sudo because /usr/local/lib/python3.x/ is root-owned.
install_python_editable() {
    local pkg_path="$1"
    if ! command -v uv >/dev/null 2>&1; then
        err "uv not found. Install uv: curl -LsSf https://astral.sh/uv/install.sh | sh"
        return 1
    fi
    sudo uv pip install --system --break-system-packages -e "$pkg_path" --quiet
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

# Ensure ORT CUDA/OpenVINO provider .so files are installed.
# Delegates to Python (corvia_dev.rebuild.ensure_ort_libs).
ensure_ort_provider_libs() {
    local restored
    restored=$(python3 -c "
from pathlib import Path
from corvia_dev.rebuild import ensure_ort_libs
print('yes' if ensure_ort_libs(Path('${WORKSPACE_ROOT}')) else 'no')
" 2>/dev/null) || true
    if [ "$restored" = "yes" ]; then
        log gpu "ORT provider libs: restored from build cache"
    fi
}

# Create /dev/dri/by-path symlinks for Intel iGPU.
# The NEO compute runtime discovers GPUs by scanning by-path.
# Docker device passthrough creates /dev/dri but may not populate by-path
# for integrated GPUs. Without this, OpenCL/OpenVINO see 0 platforms.
create_gpu_symlinks() {
    if [ ! -d /dev/dri ] || [ ! -d /dev/dri/by-path ]; then
        return 0
    fi
    for card_dir in /sys/class/drm/card*/device; do
        local card_name
        card_name="$(basename "$(dirname "$card_dir")")"
        local vendor
        vendor="$(cat "$card_dir/vendor" 2>/dev/null || true)"
        [ "$vendor" = "0x8086" ] || continue  # Intel only

        local pci_slot
        pci_slot="$(cat "$card_dir/uevent" 2>/dev/null | grep PCI_SLOT_NAME | cut -d= -f2 || true)"
        [ -n "$pci_slot" ] || continue

        # Find the renderD node for this card
        local render_node=""
        for rd in /sys/class/drm/renderD*/device; do
            local rd_vendor rd_device card_device
            rd_vendor="$(cat "$rd/vendor" 2>/dev/null || true)"
            rd_device="$(cat "$rd/device" 2>/dev/null || true)"
            card_device="$(cat "$card_dir/device" 2>/dev/null || true)"
            if [ "$rd_vendor" = "$vendor" ] && [ "$rd_device" = "$card_device" ]; then
                render_node="$(basename "$(dirname "$rd")")"
                break
            fi
        done

        # Create by-path symlinks if missing
        local card_link="/dev/dri/by-path/pci-${pci_slot}-card"
        local render_link="/dev/dri/by-path/pci-${pci_slot}-render"
        if [ ! -L "$card_link" ] && [ -e "/dev/dri/$card_name" ]; then
            ln -sf "../$card_name" "$card_link"
        fi
        if [ -n "$render_node" ] && [ ! -L "$render_link" ] && [ -e "/dev/dri/$render_node" ]; then
            ln -sf "../$render_node" "$render_link"
        fi
    done
}

# Ensure all tooling is installed (catches up if post-create was incomplete).
ensure_tooling() {
    ensure_corvia

    if ! command -v corvia-dev >/dev/null 2>&1; then
        echo "corvia-dev not found — installing..."
        retry 3 install_python_editable "$WORKSPACE_ROOT/tools/corvia-dev"
    fi
}
