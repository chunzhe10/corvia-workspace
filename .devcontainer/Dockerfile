FROM rust:1.88-trixie

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git build-essential pkg-config libssl-dev cmake protobuf-compiler \
    nodejs npm jq python3 sudo \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for devcontainer
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Pre-install all network-dependent tools in a single layer to minimize
# flaky WSL2 Docker build networking issues. All best-effort with fallback
# to runtime install via ensure_tooling in post-start.sh.
RUN set -x; \
    # uv (Python package manager) \
    curl -LsSf --retry 5 --retry-delay 3 https://astral.sh/uv/install.sh | sh \
    && mv /root/.local/bin/uv /usr/local/bin/uv \
    && mv /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv --version \
    # Python deps for corvia-dev (pydantic is heavy — cache in image) \
    && uv pip install --system --break-system-packages \
        click pydantic tomli_w setuptools \
    # gh CLI \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/* \
    # Claude Code CLI \
    && npm install -g --silent @anthropic-ai/claude-code \
    || echo "WARNING: some tool installs failed — will retry at runtime"

# Pre-create cargo registry cache so volume mounts work cleanly
ENV CARGO_HOME="/usr/local/cargo"

RUN rustup component add rust-analyzer

WORKDIR /workspaces
