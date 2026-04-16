# Auto-start corvia serve Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Start `corvia serve` automatically in the devcontainer post-start sequence so the HTTP MCP transport works out of the box.

**Architecture:** Add a new Taskfile task (`post-start:corvia-serve`) between `corvia-init` and `claude-integration` in the post-start sequence. The task guards against missing binary support, checks if already running, starts the server in the background, and verifies it's listening. Same logic is added to the bash fallback script.

**Tech Stack:** Bash, Taskfile v3 YAML, devcontainer lifecycle hooks

**Design spec:** `docs/decisions/2026-04-16-autostart-corvia-serve-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `.devcontainer/Taskfile.yml` | Modify (lines 29-37, add new task block) | Primary orchestration — add `post-start:corvia-serve` task and insert it into sequence |
| `.devcontainer/scripts/post-start.sh` | Modify (lines 28-31, add new step) | Bash fallback — same logic for environments without `task` binary |
| `.devcontainer/devcontainer.json` | Modify (line 11) | Update stale comment about MCP transport |

---

### Task 1: Add `post-start:corvia-serve` to Taskfile.yml

**Files:**
- Modify: `.devcontainer/Taskfile.yml:29-37` (post-start sequence) and after line 57 (add new task)

- [ ] **Step 1: Add corvia-serve to the post-start sequence**

In `.devcontainer/Taskfile.yml`, the `post-start` task (line 29) lists subtasks. Insert `post-start:corvia-serve` between `post-start:corvia-init` and `post-start:claude-integration`.

Change lines 29-38 from:

```yaml
  post-start:
    desc: "Full post-start sequence (devcontainer lifecycle)"
    cmds:
      - cmd: "printf '\\033[1m=== Corvia Workspace: post-start ===\\033[0m\\n'"
      - task: post-start:auth
      - task: post-start:corvia-init
      - task: post-start:claude-integration
      - task: post-start:ensure-extensions
      - task: post-start:sweep
      - cmd: "printf '\\n\\033[1;32m✓ Ready.\\033[0m\\n'"
```

to:

```yaml
  post-start:
    desc: "Full post-start sequence (devcontainer lifecycle)"
    cmds:
      - cmd: "printf '\\033[1m=== Corvia Workspace: post-start ===\\033[0m\\n'"
      - task: post-start:auth
      - task: post-start:corvia-init
      - task: post-start:corvia-serve
      - task: post-start:claude-integration
      - task: post-start:ensure-extensions
      - task: post-start:sweep
      - cmd: "printf '\\n\\033[1;32m✓ Ready.\\033[0m\\n'"
```

- [ ] **Step 2: Add the corvia-serve task definition**

Insert a new task block after `post-start:corvia-init` (after line 57). This goes between the `corvia-init` task and the `claude-integration` task.

Add this block:

```yaml
  post-start:corvia-serve:
    desc: "Start corvia serve (HTTP MCP server) in background"
    cmds:
      - |
        source {{.SCRIPT_DIR}}/lib.sh
        # 1. Capability guard — skip if binary doesn't support serve
        if ! corvia serve --help >/dev/null 2>&1; then
          logw services "corvia serve: not supported by installed binary — skipping"
          exit 0
        fi
        # 2. Already-running check — skip if port 8020 is already listening
        if bash -c 'echo > /dev/tcp/127.0.0.1/8020' 2>/dev/null; then
          logg services "corvia serve: already running on port 8020"
          exit 0
        fi
        # 3. Start server in background
        logg services "corvia serve: starting on port 8020"
        nohup corvia serve --port 8020 >> {{.WORKSPACE_ROOT}}/.corvia/serve.log 2>&1 &
        # 4. Health probe — wait up to 5s for TCP connection
        for i in 1 2 3 4 5; do
          sleep 1
          if bash -c 'echo > /dev/tcp/127.0.0.1/8020' 2>/dev/null; then
            logg services "corvia serve: ready (${i}s)"
            exit 0
          fi
        done
        logw services "corvia serve: not responding after 5s — check .corvia/serve.log"
```

- [ ] **Step 3: Verify Taskfile syntax**

Run:

```bash
task --list -d .devcontainer
```

Expected: Task list includes `post-start:corvia-serve` with description "Start corvia serve (HTTP MCP server) in background". No YAML parse errors.

- [ ] **Step 4: Commit**

```bash
git add .devcontainer/Taskfile.yml
git commit -m "feat: add post-start:corvia-serve task to Taskfile"
```

---

### Task 2: Add serve start to bash fallback (post-start.sh)

**Files:**
- Modify: `.devcontainer/scripts/post-start.sh:28-31` (insert new step)

- [ ] **Step 1: Add serve step to post-start.sh**

In `.devcontainer/scripts/post-start.sh`, insert a new step between the corvia health check (step 2/4) and Claude Code integration (step 3/4). Update step numbering from 4 total to 5 total.

Change the step count headers from `N/4` to `N/5`, and insert the new step after line 29 (the closing `fi` of the corvia health check block).

The file should become:

```bash
#!/bin/bash
# LEGACY FALLBACK — this script is used only when the `task` binary is unavailable.
# The primary setup orchestration is in .devcontainer/Taskfile.yml, invoked by
# .devcontainer/scripts/setup_wrapper.py.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

step() { printf " => %s\n" "$*"; }
done_msg() { printf "    ... done\n"; }
fail_msg() { printf "    ... FAILED (%s)\n" "$*" >&2; }

export TZ=Asia/Kuala_Lumpur

echo "=== Corvia Workspace: post-start ==="

# ── 1/5 ───────────────────────────────────────────────────────────────
step "Forwarding host authentication"
forward_host_auth

# ── 2/5 ───────────────────────────────────────────────────────────────
step "corvia health check"
if command -v corvia >/dev/null 2>&1; then
    corvia init --yes || fail_msg "corvia init failed"
else
    fail_msg "corvia not on PATH — run post-create or install manually"
fi

# ── 3/5 ───────────────────────────────────────────────────────────────
step "Starting corvia serve"
if ! corvia serve --help >/dev/null 2>&1; then
    fail_msg "corvia serve not supported by installed binary — skipping"
elif bash -c 'echo > /dev/tcp/127.0.0.1/8020' 2>/dev/null; then
    echo "    already running on port 8020"
else
    nohup corvia serve --port 8020 >> "$WORKSPACE_ROOT/.corvia/serve.log" 2>&1 &
    for i in 1 2 3 4 5; do
        sleep 1
        if bash -c 'echo > /dev/tcp/127.0.0.1/8020' 2>/dev/null; then
            done_msg
            break
        fi
    done
    if ! bash -c 'echo > /dev/tcp/127.0.0.1/8020' 2>/dev/null; then
        fail_msg "not responding after 5s — check .corvia/serve.log"
    fi
fi

# ── 4/5 ───────────────────────────────────────────────────────────────
step "Claude Code integration"
printf "    superpowers plugin: "
install_claude_plugin "https://github.com/obra/superpowers.git" superpowers claude-plugins-official \
    || fail_msg "git clone failed — check network connectivity"

# ── 5/5 ───────────────────────────────────────────────────────────────
# Sweep cargo build artifacts if disk is >70% full.
"$SCRIPT_DIR/sweep-cargo-cache.sh" || true

echo ""
echo "Ready."
```

- [ ] **Step 2: Verify script syntax**

Run:

```bash
bash -n .devcontainer/scripts/post-start.sh
```

Expected: No output (clean parse, exit 0).

- [ ] **Step 3: Commit**

```bash
git add .devcontainer/scripts/post-start.sh
git commit -m "feat: add corvia serve auto-start to bash fallback"
```

---

### Task 3: Update stale comment in devcontainer.json

**Files:**
- Modify: `.devcontainer/devcontainer.json:11`

- [ ] **Step 1: Update the comment**

In `.devcontainer/devcontainer.json`, line 11 reads:

```json
    // No ports to forward — corvia v2 uses stdio MCP (no HTTP server).
```

Change it to:

```json
    // corvia serve (HTTP MCP at 127.0.0.1:8020) is auto-started by post-start.
    // No forwardPorts needed — server binds to localhost only (container-internal).
```

- [ ] **Step 2: Verify JSON validity**

Run:

```bash
python3 -c "
import json, re
text = open('.devcontainer/devcontainer.json').read()
# Strip // comments (JSON5-style used by devcontainer)
cleaned = re.sub(r'//.*', '', text)
json.loads(cleaned)
print('valid')
"
```

Expected: `valid`

- [ ] **Step 3: Commit**

```bash
git add .devcontainer/devcontainer.json
git commit -m "chore: update devcontainer comment for HTTP MCP transport"
```

---

### Task 4: Manual smoke test

- [ ] **Step 1: Dry-run the new task**

Run:

```bash
task --dry post-start:corvia-serve -d .devcontainer
```

Expected: Shows the shell commands that would execute, no errors.

- [ ] **Step 2: Run the task (expects graceful skip on current binary)**

Run:

```bash
task post-start:corvia-serve -d .devcontainer
```

Expected: Warning message "corvia serve: not supported by installed binary — skipping" (because the installed release binary lacks the `serve` subcommand). Exit code 0 (not a failure).

- [ ] **Step 3: Verify full post-start still works**

Run:

```bash
task post-start -d .devcontainer --output interleaved
```

Expected: All steps complete. The corvia-serve step logs a skip warning. No errors from other steps.
