FROM rust:1.85-bookworm

RUN apt-get update && apt-get install -y \
    curl git build-essential pkg-config libssl-dev cmake \
    && rm -rf /var/lib/apt/lists/*

# Install Ollama
RUN curl -fsSL https://ollama.com/install.sh | sh

WORKDIR /workspace
