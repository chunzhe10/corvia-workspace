#!/bin/bash
set -euo pipefail

REPO_URL="${CORVIA_REPO_URL}"
BRANCH="${CORVIA_BRANCH:-}"
ISSUE="${CORVIA_ISSUE:-}"
MCP_URL="${CORVIA_MCP_URL:-http://app:8020/mcp}"
MCP_TOKEN="${CORVIA_MCP_TOKEN:-}"
AGENT_ID="${CORVIA_AGENT_ID:-spoke-unknown}"
SPOKE_TOKEN="${CORVIA_SPOKE_TOKEN:-}"

# --- Error reporting ---
report_failure() {
    local msg="$1"
    echo "SPOKE FAILURE: ${msg}"
    curl -sf -X POST "${MCP_URL}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${MCP_TOKEN}" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",
             \"params\":{\"name\":\"corvia_write\",\"arguments\":{
               \"scope_id\":\"corvia\",\"agent_id\":\"${AGENT_ID}\",
               \"content_role\":\"finding\",\"source_origin\":\"workspace\",
               \"content\":\"Spoke ${AGENT_ID} failed: ${msg}\"
             }}}" 2>/dev/null || true
}
trap 'report_failure "Entrypoint failed at line $LINENO (exit $?)"' ERR

# --- 1. Verify Claude Code is installed ---
if ! command -v claude &>/dev/null; then
    if [ "${ALLOW_RUNTIME_INSTALL:-}" = "1" ]; then
        echo "Warning: Installing Claude Code at runtime (slow, use pre-built image)"
        npm install -g @anthropic-ai/claude-code@latest 2>&1 | tail -3
    else
        report_failure "Claude Code not installed. Use pre-built spoke image."
        exit 1
    fi
fi

# --- 2. Setup credentials (non-root: copy from mount) ---
mkdir -p ~/.claude
cp /spoke-config/.credentials.json ~/.claude/.credentials.json 2>/dev/null || true
chmod 600 ~/.claude/.credentials.json 2>/dev/null || true

# --- 3. Clone repo (with retry) ---
REPO_OWNER=$(echo "${REPO_URL}" | sed -n 's|.*github.com[:/]\([^/]*\)/.*|\1|p')
REPO_NAME=$(echo "${REPO_URL}" | sed -n 's|.*github.com[:/][^/]*/\([^/.]*\).*|\1|p')
DEFAULT_BRANCH=$(gh api "repos/${REPO_OWNER}/${REPO_NAME}" --jq '.default_branch' 2>/dev/null || echo "master")

if [ -d "/workspace/.git" ]; then
    echo "Workspace already populated, skipping clone."
    cd /workspace
    git fetch origin && git pull --rebase || true
else
    clone_with_retry() {
        for i in 1 2 3; do
            if git clone --depth 100 --branch "${DEFAULT_BRANCH}" "${REPO_URL}" /workspace; then
                return 0
            fi
            echo "Clone failed (attempt $i/3), retrying in 5s..."
            sleep 5
        done
        return 1
    }
    if ! clone_with_retry; then
        report_failure "Git clone failed after 3 attempts"
        exit 1
    fi
    cd /workspace
fi

# --- 4. Create or checkout branch ---
# Use CORVIA_BRANCH if set (hub determines the branch name).
# Only generate from issue title when BRANCH is empty.
if [ -n "${BRANCH}" ]; then
    git checkout -b "${BRANCH}" 2>/dev/null || git checkout "${BRANCH}"
elif [ -n "${ISSUE}" ] && [ "${ISSUE}" != "0" ]; then
    ISSUE_TITLE=$(gh issue view "${ISSUE}" --repo "${REPO_OWNER}/${REPO_NAME}" --json title --jq '.title' 2>/dev/null || echo "")
    SLUG=$(echo "${ISSUE_TITLE}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | head -c 40)
    BRANCH_NAME="feat/${ISSUE}-${SLUG}"
    if git ls-remote --heads origin "${BRANCH_NAME}" | grep -q .; then
        git fetch origin "${BRANCH_NAME}" && git checkout "${BRANCH_NAME}"
    else
        git checkout -b "${BRANCH_NAME}"
    fi
fi

# --- 5. Write MCP config (outside git tree to prevent accidental commits) ---
mkdir -p ~/.claude
cat > ~/.claude/.mcp.json << EOF
{
  "mcpServers": {
    "corvia": {
      "type": "http",
      "url": "${MCP_URL}",
      "headers": {
        "Authorization": "Bearer ${MCP_TOKEN}"
      }
    }
  }
}
EOF
# Symlink into workspace for Claude Code discovery, and exclude from git
ln -sf ~/.claude/.mcp.json /workspace/.mcp.json
echo '.mcp.json' >> /workspace/.git/info/exclude

# --- 6. Copy workspace instruction files (exclude from git to avoid conflicts) ---
cp /spoke-config/AGENTS.md /workspace/AGENTS.md 2>/dev/null || true
cp /spoke-config/CLAUDE.md /workspace/CLAUDE.md 2>/dev/null || true
mkdir -p /workspace/.agents
cp -r /spoke-config/skills /workspace/.agents/skills 2>/dev/null || true
# Exclude copied files from git to prevent accidental commits
{
    echo 'AGENTS.md'
    echo 'CLAUDE.md'
    echo '.agents/'
} >> /workspace/.git/info/exclude

# --- 7. Write Claude Code settings (scoped permissions) ---
cat > ~/.claude/settings.json << EOF
{
  "permissions": {
    "allow": [
      "Bash(git *)", "Bash(cargo *)", "Bash(npm *)", "Bash(gh *)",
      "Bash(curl *)", "Bash(ls *)", "Bash(cat *)", "Bash(mkdir *)", "Bash(cp *)",
      "Read(*)", "Write(*)", "Edit(*)", "Glob(*)", "Grep(*)", "Agent(*)",
      "mcp__corvia__*"
    ]
  }
}
EOF

# --- 8. Wait for hub MCP ---
echo "Checking hub MCP connectivity..."
for i in $(seq 1 30); do
    if curl -sf -X POST "${MCP_URL}" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' >/dev/null 2>&1; then
        echo "Hub MCP reachable."
        break
    fi
    if [ "$i" -eq 30 ]; then
        report_failure "Hub MCP unreachable after 150s"
        exit 1
    fi
    sleep 5
done

# --- 9. Start Claude Code ---
EXIT_CODE=0
if [ -n "${ISSUE}" ] && [ "${ISSUE}" != "0" ]; then
    claude -p "/dev-loop ${ISSUE}" || EXIT_CODE=$?
else
    claude || EXIT_CODE=$?
fi

# --- 10. Report exit (only failures) ---
if [ "${EXIT_CODE}" -ne 0 ]; then
    report_failure "Spoke exited with error (code ${EXIT_CODE}). Issue #${ISSUE}."
fi
exit $EXIT_CODE
