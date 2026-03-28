FROM node:22-bookworm

# System tools + GitHub CLI
RUN apt-get update && apt-get install -y git curl build-essential && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

# Claude Code (pinned version, never @latest)
ARG CLAUDE_CODE_VERSION=2.1.86
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}
LABEL corvia.spoke.claude_code_version=${CLAUDE_CODE_VERSION}

# Non-root user
RUN useradd -m -s /bin/bash spoke
USER spoke
WORKDIR /workspace

# Spoke entrypoint
COPY --chown=spoke:spoke spoke-entrypoint.sh /usr/local/bin/spoke-entrypoint.sh
RUN chmod +x /usr/local/bin/spoke-entrypoint.sh

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pgrep -f "claude" || exit 1

ENTRYPOINT ["/usr/local/bin/spoke-entrypoint.sh"]
