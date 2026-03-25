#!/bin/bash
# Runs on the HOST before the container is created (initializeCommand).
# Detects GPU availability, allocates non-clashing host ports, and generates
# docker-compose.override.yml with device passthrough + port mappings.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OVERRIDE="$DC_DIR/docker-compose.override.yml"

# If the .devcontainer dir or override file aren't writable (e.g. owned by
# root from a previous Docker rebuild), fix ownership so we can write to them.
if [ ! -w "$DC_DIR" ]; then
    sudo chown -R "$(id -u):$(id -g)" "$DC_DIR"
fi
if [ -e "$OVERRIDE" ] && [ ! -w "$OVERRIDE" ]; then
    rm -f "$OVERRIDE" 2>/dev/null || sudo rm -f "$OVERRIDE"
fi

HOME_DIR="${HOME:-${USERPROFILE:-}}"
if [ -z "$HOME_DIR" ]; then
    echo "Warning: Cannot determine home directory — auth forwarding may not work"
fi

# Create directories if they don't exist so Docker bind mounts succeed.
[ -n "$HOME_DIR" ] && mkdir -p "$HOME_DIR/.config/gh" "$HOME_DIR/.claude"

# ── Ensure gh token is in hosts.yml ──────────────────────────────────
# On many systems (WSL, Linux with libsecret/gnome-keyring), gh stores the
# OAuth token in the system keyring rather than in hosts.yml. The container
# bind-mounts ~/.config/gh but can't access the host keyring. Fix: extract
# the token via `gh auth token` and write it into hosts.yml so the container
# gets a complete config.
if command -v gh >/dev/null 2>&1 && [ -n "$HOME_DIR" ]; then
    GH_HOSTS="$HOME_DIR/.config/gh/hosts.yml"
    if [ -f "$GH_HOSTS" ]; then
        # Check if hosts.yml is missing the oauth_token field
        if ! grep -q "oauth_token:" "$GH_HOSTS" 2>/dev/null; then
            GH_TOKEN_VAL=$(gh auth token 2>/dev/null || true)
            if [ -n "$GH_TOKEN_VAL" ]; then
                # Inject token under the github.com user block
                # Pass token via env to avoid shell/string escaping issues
                GH_TOKEN_VAL="$GH_TOKEN_VAL" GH_HOSTS_FILE="$GH_HOSTS" python3 -c "
import os, sys
token = os.environ['GH_TOKEN_VAL']
hosts_file = os.environ['GH_HOSTS_FILE']
try:
    import yaml
    with open(hosts_file) as f:
        data = yaml.safe_load(f) or {}
    for host in data:
        if isinstance(data[host], dict) and 'user' in data[host]:
            user = data[host]['user']
            if 'users' in data[host] and user in data[host]['users']:
                if data[host]['users'][user] is None:
                    data[host]['users'][user] = {}
                data[host]['users'][user]['oauth_token'] = token
            data[host]['oauth_token'] = token
    with open(hosts_file, 'w') as f:
        yaml.dump(data, f, default_flow_style=False)
    print('  gh: wrote token from keyring into hosts.yml')
except ImportError:
    # No PyYAML — use simple line insertion
    # Insert oauth_token under the username key in users: block
    # and at the top level for legacy compatibility
    with open(hosts_file) as f:
        content = f.read()
    with open(hosts_file) as f:
        lines = f.readlines()
    # Find the username line under users: and add token there
    in_users = False
    with open(hosts_file, 'w') as f:
        for line in lines:
            f.write(line)
            stripped = line.strip()
            if stripped == 'users:':
                in_users = True
            elif in_users and stripped.endswith(':') and not stripped.startswith('users'):
                # This is the username line (e.g. 'chunzhe10:')
                indent = len(line) - len(line.lstrip()) + 4
                f.write(' ' * indent + 'oauth_token: ' + token + '\n')
                in_users = False
            elif stripped.startswith('user:'):
                # Top-level user: line — add oauth_token after it (legacy)
                indent = len(line) - len(line.lstrip())
                f.write(' ' * indent + 'oauth_token: ' + token + '\n')
    print('  gh: wrote token from keyring into hosts.yml (fallback)')
" 2>/dev/null || echo "  gh: warning — could not write token to hosts.yml"
            fi
        fi
    fi
fi

# ── Remove stale containers ─────────────────────────────────────────
# VS Code uses `docker compose up --no-recreate` which reuses existing
# containers even when the compose config has changed (e.g. tty, mounts).
# Remove any exited containers for this workspace so they get recreated
# with the current config.
WORKSPACE_DIR="$(cd "$DC_DIR/.." && pwd)"
STALE_IDS=$(docker ps -q -a \
    --filter "label=devcontainer.local_folder=$WORKSPACE_DIR" \
    --filter "status=exited" 2>/dev/null || true)
if [ -n "$STALE_IDS" ]; then
    echo "Removing exited devcontainer(s) to ensure fresh config..."
    echo "$STALE_IDS" | xargs docker rm 2>/dev/null || true
fi

# ── Port allocation ──────────────────────────────────────────────────
# Derive deterministic host-port offset from workspace directory name.
# "corvia-workspace" → offset 0, "corvia-workspace-2" → offset 200, etc.
# Container-internal ports stay fixed (8020/8021/8030/11434); only the
# host↔container mapping changes. Override: set CORVIA_PORT_OFFSET on host.

# Check if a host port is in use. Works on Linux (ss) and macOS (lsof).
port_in_use() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -tln 2>/dev/null | grep -q ":${port} "
    elif command -v lsof >/dev/null 2>&1; then
        lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    else
        return 1  # can't check, assume free
    fi
}

# Try computed port, if in use increment by 1 up to 10 attempts.
# Tracks claimed ports via a temp file (bash subshells from $() can't
# modify parent arrays, so we use a file for cross-call coordination).
CLAIMED_FILE=$(mktemp)
trap 'rm -f "$CLAIMED_FILE"' EXIT

find_free_port() {
    local base="$1"
    local name="${2:-}"  # optional label for logging
    local port
    for i in $(seq 0 10); do
        port=$(( base + i ))
        # Skip ports already claimed by earlier calls in this script
        if grep -qx "$port" "$CLAIMED_FILE" 2>/dev/null; then
            continue
        fi
        if ! port_in_use "$port"; then
            echo "$port" >> "$CLAIMED_FILE"
            [ "$i" -gt 0 ] && [ -n "$name" ] && echo "  Port $base in use, using $port for $name" >&2
            echo "$port"
            return 0
        fi
    done
    # Give up — Docker will error clearly at bind time.
    echo "$base" >> "$CLAIMED_FILE"
    echo "$base"
    return 0
}

WORKSPACE_NAME="$(basename "$WORKSPACE_DIR")"
WORKSPACE_NUM=$(echo "$WORKSPACE_NAME" | grep -oE '[0-9]+$' || true)
[ -z "$WORKSPACE_NUM" ] && WORKSPACE_NUM=1
PORT_OFFSET="${CORVIA_PORT_OFFSET:-$(( (WORKSPACE_NUM - 1) * 200 ))}"

# Validate PORT_OFFSET is numeric (CORVIA_PORT_OFFSET could be anything)
if ! [[ "$PORT_OFFSET" =~ ^[0-9]+$ ]]; then
    echo "ERROR: CORVIA_PORT_OFFSET='$PORT_OFFSET' is not a valid number."
    exit 1
fi

# Sanity cap: offset must keep ports within valid range (max 65535)
if [ "$PORT_OFFSET" -gt 57000 ]; then
    echo "ERROR: Port offset $PORT_OFFSET too high (workspace number too large)."
    echo "       Use CORVIA_PORT_OFFSET env var to set a custom offset."
    exit 1
fi

HOST_API=$(find_free_port $(( 8020 + PORT_OFFSET )) "api")
HOST_VITE=$(find_free_port $(( 8021 + PORT_OFFSET )) "vite")
HOST_INFERENCE=$(find_free_port $(( 8030 + PORT_OFFSET )) "inference")
HOST_OLLAMA=$(find_free_port $(( 11434 + PORT_OFFSET )) "ollama")

# ── Platform detection ───────────────────────────────────────────────
IS_WSL=false
if grep -qi "microsoft\|wsl" /proc/version 2>/dev/null; then
    IS_WSL=true
    echo "Platform: WSL"
elif [ "$(uname -s)" = "Linux" ]; then
    echo "Platform: native Linux"
else
    echo "Platform: $(uname -s)"
fi

# ── GPU detection ────────────────────────────────────────────────────
HAS_NVIDIA=false
HAS_DRI=false
HAS_DXG=false

# NVIDIA: check for nvidia-smi and nvidia-container-toolkit
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    if command -v nvidia-container-cli >/dev/null 2>&1 || \
       [ -f /usr/bin/nvidia-container-runtime ]; then
        HAS_NVIDIA=true
        # Ensure CDI spec exists and matches the running driver version.
        # Docker uses CDI to discover GPUs; a missing or stale spec causes
        # "could not select device driver nvidia" even when the driver works.
        if command -v nvidia-ctk >/dev/null 2>&1; then
            RUNNING_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || true)
            # If grep pattern fails (CDI format change), CDI_DRIVER will be empty
            # and we'll regenerate — safe, since generation is idempotent.
            CDI_DRIVER=$(grep -oP 'host-driver-version=\K[0-9.]+' /etc/cdi/nvidia.yaml 2>/dev/null | head -1 || true)
            if [ -z "$RUNNING_DRIVER" ]; then
                echo "GPU: Warning — could not determine driver version, skipping CDI check"
            elif [ ! -f /etc/cdi/nvidia.yaml ] || [ "$RUNNING_DRIVER" != "$CDI_DRIVER" ]; then
                echo "GPU: Regenerating NVIDIA CDI spec (driver: $RUNNING_DRIVER)..."
                if ! sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml >/dev/null 2>&1; then
                    echo "GPU: Warning — CDI spec regeneration failed (non-fatal)"
                fi
            fi
        else
            echo "GPU: nvidia-ctk not found — CDI spec may be stale after driver changes"
            echo "     Install nvidia-container-toolkit for automatic CDI management"
        fi
    else
        echo "GPU: NVIDIA GPU found but nvidia-container-toolkit not installed"
        echo "     Install it for GPU passthrough: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/"
        echo "     Ollama will run CPU-only until the toolkit is installed."
    fi
fi

# DRI render nodes (/dev/dri) — used by Intel, AMD, and sometimes NVIDIA
if [ -d /dev/dri ] && ls /dev/dri/renderD* >/dev/null 2>&1; then
    HAS_DRI=true
fi

# WSL2 DirectX GPU passthrough
if [ "$IS_WSL" = true ] && [ -e /dev/dxg ]; then
    HAS_DXG=true
fi

# ── Generate docker-compose.override.yml ─────────────────────────────
{
    echo "# Auto-generated by init-host.sh — do not edit manually."

    echo "services:"
    echo "  app:"

    # Port mapping (always emitted — maps host ports to fixed container ports)
    echo "    ports:"
    echo "      - \"$HOST_API:8020\""
    echo "      - \"$HOST_VITE:8021\""
    echo "      - \"$HOST_INFERENCE:8030\""
    echo "      - \"$HOST_OLLAMA:11434\""

    if [ "$HAS_NVIDIA" = false ] && [ "$HAS_DRI" = false ] && [ "$HAS_DXG" = false ]; then
        GPU_SUMMARY="No GPU detected — running CPU-only"
        echo "    # $GPU_SUMMARY"
    else
        GPU_SUMMARY="nvidia=$HAS_NVIDIA dri=$HAS_DRI wsl_dxg=$HAS_DXG"
        echo "    # GPU: $GPU_SUMMARY"

        # Collect devices, groups, and volumes into arrays (emitted once each)
        DEVICES=()
        GROUP_ADD=()
        VOLUMES=()

        if [ "$HAS_DRI" = true ]; then
            DEVICES+=("/dev/dri:/dev/dri")
            # Use numeric GIDs — group names may not exist inside the container.
            VIDEO_GID=$(getent group video 2>/dev/null | cut -d: -f3 || true)
            RENDER_GID=$(getent group render 2>/dev/null | cut -d: -f3 || true)
            [ -n "$VIDEO_GID" ] && GROUP_ADD+=("$VIDEO_GID")
            [ -n "$RENDER_GID" ] && GROUP_ADD+=("$RENDER_GID")
        fi

        if [ "$HAS_DXG" = true ]; then
            DEVICES+=("/dev/dxg:/dev/dxg")
        fi

        # Collect volumes into single array (FIX: was emitting `volumes:` twice)
        [ -d /lib/firmware/i915 ] && VOLUMES+=("/lib/firmware/i915:/lib/firmware/i915:ro")
        [ "$IS_WSL" = true ] && [ -d /usr/lib/wsl/lib ] && VOLUMES+=("/usr/lib/wsl:/usr/lib/wsl:ro")

        # Emit devices
        if [ ${#DEVICES[@]} -gt 0 ]; then
            echo "    devices:"
            for d in "${DEVICES[@]}"; do
                echo "      - $d"
            done
        fi

        # Emit group_add
        if [ ${#GROUP_ADD[@]} -gt 0 ]; then
            echo "    group_add:"
            for g in "${GROUP_ADD[@]}"; do
                echo "      - $g"
            done
        fi

        # CAP_PERFMON for intel_gpu_top GPU monitoring (i915 PMU)
        if [ "$HAS_DRI" = true ]; then
            echo "    cap_add:"
            echo "      - PERFMON"
        fi

        # Emit volumes (single block — fixes duplicate key bug)
        if [ ${#VOLUMES[@]} -gt 0 ]; then
            echo "    volumes:"
            for v in "${VOLUMES[@]}"; do
                echo "      - $v"
            done
        fi

        # NVIDIA container toolkit (uses deploy.resources for compose v2)
        if [ "$HAS_NVIDIA" = true ]; then
            echo "    deploy:"
            echo "      resources:"
            echo "        reservations:"
            echo "          devices:"
            echo "            - driver: nvidia"
            echo "              count: all"
            echo "              capabilities: [gpu]"
        fi
    fi
} > "$OVERRIDE"

# ── Port manifest + summary ──────────────────────────────────────────
# Write port manifest so users and scripts can discover allocated ports.
cat > "$DC_DIR/.port-manifest.json" <<MANIFEST
{
  "workspace": "$WORKSPACE_NAME",
  "offset": $PORT_OFFSET,
  "host": { "api": $HOST_API, "vite": $HOST_VITE, "inference": $HOST_INFERENCE, "ollama": $HOST_OLLAMA },
  "container": { "api": 8020, "vite": 8021, "inference": 8030, "ollama": 11434 }
}
MANIFEST

echo "GPU: $GPU_SUMMARY"
echo ""
echo "=== $WORKSPACE_NAME ports ==="
echo "  API + Dashboard:  http://localhost:$HOST_API"
echo "  Vite dev server:  http://localhost:$HOST_VITE"
echo "  Inference gRPC:   localhost:$HOST_INFERENCE"
echo "  Ollama:           localhost:$HOST_OLLAMA"
echo ""
echo "Host init complete."
