FROM mcr.microsoft.com/playwright:latest AS playwright
FROM ghcr.io/astral-sh/uv:latest AS uv

FROM rust:1.88-trixie

COPY --from=uv /uv /usr/local/bin/uv
COPY --from=uv /uvx /usr/local/bin/uvx

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git build-essential pkg-config libssl-dev libclang-dev cmake protobuf-compiler \
    nodejs npm jq python3 sudo zstd \
    && rm -rf /var/lib/apt/lists/*

# Intel GPU compute runtime (needed by Ollama for iGPU inference).
# Packages aren't in Debian trixie repos — install from Intel's GitHub releases.
# Only available for amd64; skip on other architectures.
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
        apt-get update && apt-get install -y --no-install-recommends ocl-icd-libopencl1 \
        && rm -rf /var/lib/apt/lists/* \
        && mkdir -p /tmp/intel-gpu && cd /tmp/intel-gpu \
        && curl -LO https://github.com/intel/compute-runtime/releases/download/26.05.37020.3/libigdgmm12_22.9.0_amd64.deb \
        && curl -LO https://github.com/intel/intel-graphics-compiler/releases/download/v2.28.4/intel-igc-core-2_2.28.4%2B20760_amd64.deb \
        && curl -LO https://github.com/intel/intel-graphics-compiler/releases/download/v2.28.4/intel-igc-opencl-2_2.28.4%2B20760_amd64.deb \
        && curl -LO https://github.com/intel/compute-runtime/releases/download/26.05.37020.3/intel-opencl-icd_26.05.37020.3-0_amd64.deb \
        && curl -LO https://github.com/intel/compute-runtime/releases/download/26.05.37020.3/libze-intel-gpu1_26.05.37020.3-0_amd64.deb \
        && dpkg -i libigdgmm12_*.deb intel-igc-core-2_*.deb intel-igc-opencl-2_*.deb \
                  intel-opencl-icd_*.deb libze-intel-gpu1_*.deb \
        && rm -rf /tmp/intel-gpu; \
    else \
        echo "Skipping Intel GPU packages (not amd64)"; \
    fi

# OpenVINO 2025.3.0 runtime (needed by corvia-inference ONNX Runtime OpenVINO EP).
# Matches ort 2.0.0-rc.11 → ONNX Runtime 1.23.2 → OpenVINO 2025.3.0.
# libtbb12 not in Debian trixie — pull from Ubuntu Noble; libhwloc15 is in trixie.
# Only available for amd64; skip on other architectures.
RUN if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
        apt-get update && apt-get install -y --no-install-recommends libhwloc15 \
        && rm -rf /var/lib/apt/lists/* \
        && mkdir -p /tmp/tbb && cd /tmp/tbb \
        && curl -LO http://mirrors.kernel.org/ubuntu/pool/universe/o/onetbb/libtbbmalloc2_2021.11.0-2ubuntu2_amd64.deb \
        && curl -LO http://mirrors.kernel.org/ubuntu/pool/universe/o/onetbb/libtbbbind-2-5_2021.11.0-2ubuntu2_amd64.deb \
        && curl -LO http://mirrors.kernel.org/ubuntu/pool/universe/o/onetbb/libtbb12_2021.11.0-2ubuntu2_amd64.deb \
        && dpkg -i libtbbmalloc2_*.deb libtbbbind-2-5_*.deb libtbb12_*.deb \
        && rm -rf /tmp/tbb \
        && wget -qO- https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB \
            | gpg --dearmor -o /usr/share/keyrings/openvino-archive-keyring.gpg \
        && echo "deb [signed-by=/usr/share/keyrings/openvino-archive-keyring.gpg] https://apt.repos.intel.com/openvino/2025 ubuntu24 main" \
            > /etc/apt/sources.list.d/intel-openvino.list \
        && apt-get update && apt-get install -y --no-install-recommends \
            libopenvino-2025.3.0 \
            libopenvino-intel-gpu-plugin-2025.3.0 \
            libopenvino-onnx-frontend-2025.3.0 \
        && rm -rf /var/lib/apt/lists/* \
        && ln -sf /usr/lib/libopenvino.so.2530 /usr/lib/libopenvino.so \
        && ln -sf /usr/lib/libopenvino_c.so.2530 /usr/lib/libopenvino_c.so \
        && ldconfig; \
    else \
        echo "Skipping OpenVINO packages (not amd64)"; \
    fi

# Ollama (uses iGPU when /dev/dri is available, falls back to CPU)
RUN curl -fsSL https://ollama.com/install.sh | sh

# Ensure GPU groups exist so Docker group_add resolves by name or GID.
RUN groupadd -f video && groupadd -f render

# Create non-root user for devcontainer
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID
RUN (getent group $USER_GID >/dev/null 2>&1 || groupadd --gid $USER_GID $USERNAME) \
    && (getent passwd $USER_UID >/dev/null 2>&1 || useradd --uid $USER_UID --gid $USER_GID -m $USERNAME) \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# uv is copied from the official image (multi-stage above).
# Pre-install Python deps needed by corvia-dev.
RUN uv pip install --system --break-system-packages \
        click pydantic tomli_w setuptools

RUN { curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*; } \
    || { rm -rf /var/lib/apt/lists/*; echo "WARNING: gh CLI install failed — will retry at runtime"; }

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
