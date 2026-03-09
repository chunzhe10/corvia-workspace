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
    if ! curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
        echo "  Starting Ollama server..."
        ollama serve &
        for i in $(seq 1 30); do
            curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
            sleep 1
        done
        if ! curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
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
        curl -sf http://127.0.0.1:8000/health >/dev/null 2>&1 && break
        sleep 1
    done
    if ! curl -sf http://127.0.0.1:8000/health >/dev/null 2>&1; then
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

# --- Coding LLM (Ollama + coding models + Continue config) ---

CONTINUE_CONFIG="$WORKSPACE_ROOT/.continue/config.yaml"

CODING_CHAT_MODEL="${CORVIA_CODING_CHAT_MODEL:-qwen2.5-coder:7b}"
CODING_AUTOCOMPLETE_MODEL="${CORVIA_CODING_AUTOCOMPLETE_MODEL:-qwen2.5-coder:1.5b}"

enable_coding_llm() {
    echo "Setting up local coding LLM..."

    # Step 1: Enable Ollama (install + start + embedding model)
    enable_ollama

    # Step 2: Pull coding models
    echo "  Pulling coding models..."
    if ! ollama list 2>/dev/null | grep -q "$CODING_CHAT_MODEL"; then
        echo "  Pulling $CODING_CHAT_MODEL (chat)..."
        ollama pull "$CODING_CHAT_MODEL"
    else
        echo "  $CODING_CHAT_MODEL already available"
    fi

    if ! ollama list 2>/dev/null | grep -q "$CODING_AUTOCOMPLETE_MODEL"; then
        echo "  Pulling $CODING_AUTOCOMPLETE_MODEL (autocomplete)..."
        ollama pull "$CODING_AUTOCOMPLETE_MODEL"
    else
        echo "  $CODING_AUTOCOMPLETE_MODEL already available"
    fi

    # Step 3: Write Continue extension config
    echo "  Configuring Continue extension..."
    mkdir -p "$(dirname "$CONTINUE_CONFIG")"
    cat > "$CONTINUE_CONFIG" <<EOF
models:
  - name: $(echo "$CODING_CHAT_MODEL" | sed 's/:/ /' | awk '{print toupper(substr($1,1,1)) substr($1,2) " " $2}')
    provider: ollama
    model: $CODING_CHAT_MODEL
    apiBase: http://localhost:11434

tabAutocompleteModel:
  name: $(echo "$CODING_AUTOCOMPLETE_MODEL" | sed 's/:/ /' | awk '{print toupper(substr($1,1,1)) substr($1,2) " " $2}')
  provider: ollama
  model: $CODING_AUTOCOMPLETE_MODEL
  apiBase: http://localhost:11434
EOF

    set_flag coding-llm enabled
    echo ""
    echo "  Local coding LLM ready!"
    echo "    Chat model:         $CODING_CHAT_MODEL"
    echo "    Autocomplete model: $CODING_AUTOCOMPLETE_MODEL"
    echo "    Continue config:    $CONTINUE_CONFIG"
    echo ""
    echo "  Override models with env vars:"
    echo "    CORVIA_CODING_CHAT_MODEL=deepseek-coder-v2:16b"
    echo "    CORVIA_CODING_AUTOCOMPLETE_MODEL=qwen2.5-coder:3b"
}

disable_coding_llm() {
    echo "Disabling local coding LLM..."

    # Remove Continue config
    if [ -f "$CONTINUE_CONFIG" ]; then
        rm "$CONTINUE_CONFIG"
        echo "  Removed Continue config"
    fi

    # Remove coding models (keep embedding model for corvia)
    if command -v ollama &>/dev/null && curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
        echo "  Removing coding models..."
        ollama rm "$CODING_CHAT_MODEL" 2>/dev/null || true
        ollama rm "$CODING_AUTOCOMPLETE_MODEL" 2>/dev/null || true
    fi

    set_flag coding-llm disabled
    echo "  Coding LLM disabled. Ollama left running for embeddings (disable separately with 'corvia-workspace disable ollama')."
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
    if curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
        ollama_running="yes"
    fi
    printf "  %-12s enabled=%-8s running=%s\n" "ollama" "$ollama_flag" "$ollama_running"

    # SurrealDB
    local surreal_flag
    surreal_flag=$(get_flag surrealdb)
    local surreal_running="no"
    if curl -sf http://127.0.0.1:8000/health >/dev/null 2>&1; then
        surreal_running="yes"
    fi
    printf "  %-12s enabled=%-8s running=%s\n" "surrealdb" "$surreal_flag" "$surreal_running"

    # Coding LLM
    local coding_flag
    coding_flag=$(get_flag coding-llm)
    printf "  %-12s enabled=%-8s\n" "coding-llm" "${coding_flag:-disabled}"

    # Corvia server (auto-heal if supervisor is dead)
    local corvia_running="no"
    local corvia_healthy="no"
    local supervisor_running="no"
    local server_pid="—"
    local supervisor_pid="—"
    local inference_running="no"

    if [ -f /tmp/corvia-supervisor.pid ] && kill -0 "$(cat /tmp/corvia-supervisor.pid)" 2>/dev/null; then
        supervisor_running="yes"
        supervisor_pid=$(cat /tmp/corvia-supervisor.pid)
    fi
    if [ -f /tmp/corvia-server.pid ] && kill -0 "$(cat /tmp/corvia-server.pid)" 2>/dev/null; then
        corvia_running="yes"
        server_pid=$(cat /tmp/corvia-server.pid)
    fi
    if curl -sf http://127.0.0.1:8020/health >/dev/null 2>&1; then
        corvia_healthy="yes"
    fi
    if curl -sf http://127.0.0.1:8030/health >/dev/null 2>&1; then
        inference_running="yes"
    fi

    echo "  corvia-server:"
    echo "    process:    ${corvia_running} (pid ${server_pid})"
    echo "    health:     ${corvia_healthy} (http://127.0.0.1:8020/health)"
    echo "    supervised: ${supervisor_running} (pid ${supervisor_pid})"
    echo "  corvia-inference:"
    echo "    health:     ${inference_running} (http://127.0.0.1:8030/health)"

    # Summary health
    echo ""
    if [ "$corvia_healthy" = "yes" ] && [ "$supervisor_running" = "yes" ]; then
        echo "  ✓ Corvia server healthy and supervised"
    elif [ "$corvia_healthy" = "yes" ] && [ "$supervisor_running" = "no" ]; then
        echo "  ⚠ Corvia server healthy but NOT supervised (no auto-restart on crash)"
    else
        echo "  ✗ Corvia server NOT healthy"
    fi

    # Auto-heal: restart supervisor if it's not running
    if [ "$supervisor_running" = "no" ]; then
        echo ""
        echo "  Auto-healing: restarting corvia supervisor..."
        # Kill any orphaned corvia serve processes
        pkill -f "corvia serve" 2>/dev/null || true
        sleep 0.5
        "$WORKSPACE_ROOT/.devcontainer/scripts/corvia-supervisor.sh" serve &
        sleep 2
        if [ -f /tmp/corvia-server.pid ] && kill -0 "$(cat /tmp/corvia-server.pid)" 2>/dev/null; then
            echo "  ✓ Supervisor started (server pid $(cat /tmp/corvia-server.pid))"
            echo "    Note: server may take ~30s to become healthy (loading index)"
        else
            echo "  ✗ Failed to start. Check /tmp/corvia-supervisor.log"
        fi
    fi

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

    # Restart corvia via supervisor
    echo "  Restarting Corvia server..."
    # Stop existing supervisor + server
    if [ -f /tmp/corvia-supervisor.pid ]; then
        kill "$(cat /tmp/corvia-supervisor.pid)" 2>/dev/null || true
    fi
    pkill -f "corvia serve" 2>/dev/null || true
    sleep 1
    "$WORKSPACE_ROOT/.devcontainer/scripts/corvia-supervisor.sh" serve &
    sleep 2
    if curl -sf http://127.0.0.1:8020/health >/dev/null 2>&1; then
        echo "  Corvia server restarted (pid $(cat /tmp/corvia-server.pid 2>/dev/null || echo '?'))."
    else
        err "Corvia server failed to restart after rebuild. Check /tmp/corvia-supervisor.log"
        exit 1
    fi
}

# --- Main ---

case "${1:-}" in
    enable)
        case "${2:-}" in
            ollama)      enable_ollama ;;
            surrealdb)   enable_surrealdb ;;
            coding-llm)  enable_coding_llm ;;
            *)           echo "Usage: corvia-workspace enable {ollama|surrealdb|coding-llm}"; exit 1 ;;
        esac
        ;;
    disable)
        case "${2:-}" in
            ollama)      disable_ollama ;;
            surrealdb)   disable_surrealdb ;;
            coding-llm)  disable_coding_llm ;;
            *)           echo "Usage: corvia-workspace disable {ollama|surrealdb|coding-llm}"; exit 1 ;;
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
        echo "  corvia-workspace enable {ollama|surrealdb|coding-llm}"
        echo "  corvia-workspace disable {ollama|surrealdb|coding-llm}"
        echo "  corvia-workspace status"
        echo "  corvia-workspace rebuild"
        exit 1
        ;;
esac
