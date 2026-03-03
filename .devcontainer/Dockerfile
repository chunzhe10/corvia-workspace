FROM rust:1.88-bookworm

RUN apt-get update && apt-get install -y \
    curl git build-essential pkg-config libssl-dev cmake protobuf-compiler \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
