#!/bin/bash
set -euo pipefail

# corvia-workspace — toggle optional devcontainer services
# Usage: corvia-workspace {enable|disable|status|rebuild} [ollama|surrealdb]

err() { echo "Error: $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
WORKSPACE_ROOT="${CORVIA_WORKSPACE:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
FLAGS_FILE="$WORKSPACE_ROOT/.devcontainer/.corvia-workspace-flags"
CORVIA_TOML="$WORKSPACE_ROOT/corvia.toml"

# Ensure flags file exists with defaults
init_flags() {
    if [ ! -f "$FLAGS_FILE" ]; then
        cat > "$FLAGS_FILE" <<'EOF'
ollama=disabled
surrealdb=disabled
EOF
    fi
}

get_flag() {
    init_flags
    grep "^$1=" "$FLAGS_FILE" | cut -d= -f2
}

set_flag() {
    init_flags
    if grep -q "^$1=" "$FLAGS_FILE"; then
        sed -i "s/^$1=.*/$1=$2/" "$FLAGS_FILE"
    else
        echo "$1=$2" >> "$FLAGS_FILE"
    fi
}

# --- Ollama ---

enable_ollama() {
    echo "Enabling Ollama..."

    # Install if not present
    if ! command -v ollama &>/dev/null; then
        echo "  Installing Ollama..."
        curl -fsSL https://ollama.com/install.sh | sh
    fi

    # Start server if not running
    if ! curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "  Starting Ollama server..."
        ollama serve &
        for i in $(seq 1 30); do
            curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && break
            sleep 1
        done
        if ! curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
            err "Ollama failed to start within 30 seconds"
            exit 1
        fi
    fi

    # Pull model if needed
    if ! ollama list 2>/dev/null | grep -q "nomic-embed-text"; then
        echo "  Pulling nomic-embed-text model..."
        ollama pull nomic-embed-text
    fi

    # Update corvia.toml
    sed -i 's/^provider = "corvia"/provider = "ollama"/' "$CORVIA_TOML"
    sed -i 's/^model = "nomic-embed-text-v1.5"/model = "nomic-embed-text"/' "$CORVIA_TOML"
    sed -i 's|^url = "http://127.0.0.1:8030"|url = "http://127.0.0.1:11434"|' "$CORVIA_TOML"

    set_flag ollama enabled
    echo "  Ollama enabled. Embedding provider switched to Ollama."
}

disable_ollama() {
    echo "Disabling Ollama..."

    # Stop server
    pkill -f "ollama serve" 2>/dev/null || true

    # Revert corvia.toml
    sed -i 's/^provider = "ollama"/provider = "corvia"/' "$CORVIA_TOML"
    sed -i 's/^model = "nomic-embed-text"$/model = "nomic-embed-text-v1.5"/' "$CORVIA_TOML"
    sed -i 's|^url = "http://127.0.0.1:11434"|url = "http://127.0.0.1:8030"|' "$CORVIA_TOML"

    set_flag ollama disabled
    echo "  Ollama disabled. Embedding provider switched to corvia-inference (ONNX)."
}

# --- SurrealDB ---

enable_surrealdb() {
    echo "Enabling SurrealDB..."

    local compose_file="$WORKSPACE_ROOT/repos/corvia/docker/docker-compose.yml"

    if [ ! -f "$compose_file" ]; then
        err "docker-compose.yml not found at $compose_file"
        exit 1
    fi

    docker compose -f "$compose_file" up -d

    # Wait for readiness
    echo "  Waiting for SurrealDB..."
    for i in $(seq 1 30); do
        curl -sf http://localhost:8000/health >/dev/null 2>&1 && break
        sleep 1
    done
    if ! curl -sf http://localhost:8000/health >/dev/null 2>&1; then
        err "SurrealDB failed to start within 30 seconds"
        exit 1
    fi

    # Update corvia.toml
    sed -i 's/^store_type = "lite"/store_type = "surrealdb"/' "$CORVIA_TOML"

    set_flag surrealdb enabled
    echo "  SurrealDB enabled. Storage switched to SurrealStore."
}

disable_surrealdb() {
    echo "Disabling SurrealDB..."

    local compose_file="$WORKSPACE_ROOT/repos/corvia/docker/docker-compose.yml"

    if [ -f "$compose_file" ]; then
        docker compose -f "$compose_file" down 2>/dev/null || true
    fi

    # Revert corvia.toml
    sed -i 's/^store_type = "surrealdb"/store_type = "lite"/' "$CORVIA_TOML"

    set_flag surrealdb disabled
    echo "  SurrealDB disabled. Storage switched to LiteStore."
}

# --- Status ---

show_status() {
    init_flags
    echo "=== Corvia Workspace Services ==="
    echo ""

    # Ollama
    local ollama_flag
    ollama_flag=$(get_flag ollama)
    local ollama_running="no"
    if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
        ollama_running="yes"
    fi
    printf "  %-12s enabled=%-8s running=%s\n" "ollama" "$ollama_flag" "$ollama_running"

    # SurrealDB
    local surreal_flag
    surreal_flag=$(get_flag surrealdb)
    local surreal_running="no"
    if curl -sf http://localhost:8000/health >/dev/null 2>&1; then
        surreal_running="yes"
    fi
    printf "  %-12s enabled=%-8s running=%s\n" "surrealdb" "$surreal_flag" "$surreal_running"

    # Corvia server
    local corvia_running="no"
    if curl -sf http://localhost:8020/health >/dev/null 2>&1; then
        corvia_running="yes"
    fi
    printf "  %-12s enabled=%-8s running=%s\n" "corvia" "always" "$corvia_running"

    echo ""

    # Show current config
    local provider model store_type
    provider=$(grep '^provider' "$CORVIA_TOML" | head -1 | cut -d'"' -f2)
    model=$(grep '^model' "$CORVIA_TOML" | head -1 | cut -d'"' -f2)
    store_type=$(grep '^store_type' "$CORVIA_TOML" | head -1 | cut -d'"' -f2)
    echo "  Config: provider=$provider model=$model store=$store_type"
}

# --- Rebuild ---

rebuild_binaries() {
    echo "Rebuilding Corvia binaries from local source..."

    local corvia_src="$WORKSPACE_ROOT/repos/corvia"

    if [ ! -d "$corvia_src" ]; then
        err "corvia source not found at $corvia_src"
        exit 1
    fi

    cd "$corvia_src"
    cargo build --release -p corvia-cli -p corvia-inference
    cp target/release/corvia /usr/local/bin/corvia
    cp target/release/corvia-inference /usr/local/bin/corvia-inference
    chmod +x /usr/local/bin/corvia /usr/local/bin/corvia-inference
    cd "$WORKSPACE_ROOT"

    echo "  Binaries rebuilt and installed to /usr/local/bin."

    # Restart corvia server if running
    if pkill -f "corvia serve" 2>/dev/null; then
        echo "  Restarting Corvia server..."
        /usr/local/bin/corvia serve --mcp &
        local pid=$!
        sleep 1
        if ! kill -0 "$pid" 2>/dev/null; then
            err "Corvia server failed to restart after rebuild."
            exit 1
        fi
        echo "  Corvia server restarted (pid $pid)."
    fi
}

# --- Main ---

case "${1:-}" in
    enable)
        case "${2:-}" in
            ollama)    enable_ollama ;;
            surrealdb) enable_surrealdb ;;
            *)         echo "Usage: corvia-workspace enable {ollama|surrealdb}"; exit 1 ;;
        esac
        ;;
    disable)
        case "${2:-}" in
            ollama)    disable_ollama ;;
            surrealdb) disable_surrealdb ;;
            *)         echo "Usage: corvia-workspace disable {ollama|surrealdb}"; exit 1 ;;
        esac
        ;;
    status)
        show_status
        ;;
    rebuild)
        rebuild_binaries
        ;;
    *)
        echo "corvia-workspace — toggle optional devcontainer services"
        echo ""
        echo "Usage:"
        echo "  corvia-workspace enable {ollama|surrealdb}"
        echo "  corvia-workspace disable {ollama|surrealdb}"
        echo "  corvia-workspace status"
        echo "  corvia-workspace rebuild"
        exit 1
        ;;
esac
