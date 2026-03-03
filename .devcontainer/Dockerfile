FROM rust:1.88-bookworm

RUN apt-get update && apt-get install -y \
    curl git build-essential pkg-config libssl-dev cmake protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

# Install Ollama
RUN curl -fsSL https://ollama.com/install.sh | sh

WORKDIR /workspace
