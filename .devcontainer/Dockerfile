FROM mcr.microsoft.com/playwright:latest AS playwright
FROM ghcr.io/astral-sh/uv:latest AS uv

FROM rust:1.88-trixie

COPY --from=uv /uv /usr/local/bin/uv
COPY --from=uv /uvx /usr/local/bin/uvx

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

# uv is copied from the official image (multi-stage above).
# Pre-install Python deps needed by corvia-dev.
RUN uv pip install --system --break-system-packages \
        click pydantic tomli_w setuptools

RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/* \
    || echo "WARNING: gh CLI install failed — will retry at runtime"

RUN npm install -g --silent @anthropic-ai/claude-code \
    || echo "WARNING: claude-code install failed — will retry at runtime"

RUN npm install -g --silent @vscode/vsce \
    || echo "WARNING: vsce install failed — will retry at runtime"

# Playwright MCP: pre-built Chromium from official image (fast, no download)
COPY --from=playwright /ms-playwright /ms-playwright
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN npx -y playwright@latest install-deps chromium \
    || echo "WARNING: playwright system deps install failed — visual QA unavailable"

# Pre-create cargo registry cache so volume mounts work cleanly
ENV CARGO_HOME="/usr/local/cargo"

RUN rustup component add rust-analyzer

WORKDIR /workspaces
