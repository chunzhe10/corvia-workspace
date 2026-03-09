FROM rust:1.88-trixie

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git build-essential pkg-config libssl-dev cmake protobuf-compiler \
    nodejs npm jq \
    && rm -rf /var/lib/apt/lists/*

# Optional: install gh CLI (best-effort, non-blocking)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/* \
    || echo "gh CLI install skipped (network unavailable)"

# Create non-root user for devcontainer
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt-get update && apt-get install -y sudo \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && rm -rf /var/lib/apt/lists/*

# Pre-create cargo registry cache so volume mounts work cleanly
ENV CARGO_HOME="/usr/local/cargo"

WORKDIR /workspaces
