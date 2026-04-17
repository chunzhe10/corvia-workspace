# MCP access: HTTP default / stdio deprecated — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist the workspace-side half of the MCP-access fix: keep `.mcp.json` on HTTP, delete the untracked stdio workaround, convert the silent-skip capability guard in `post-start:corvia-serve` to a loud failure (and promote the TCP-probe timeout to a hard failure), mirror the contract in the bash fallback, and strip stale `corvia workspace ...` references from `AGENTS.md`.

**Architecture:** Edit-only change. No new files. Adds one helper (`loge`) to `lib.sh`. Behavior change is localized to two scripts (`Taskfile.yml`, `post-start.sh`) and one docs file (`AGENTS.md`). The untracked stdio workaround file is removed.

**Tech Stack:** Bash, go-task (Taskfile.yml v3), markdown.

**Reference spec:** `docs/decisions/2026-04-17-mcp-access-http-default-design.md`

**Context already validated (no [POC] tasks needed):**
- `lib.sh` has `log`/`logg`/`logm`/`logw` but no `loge`. Plan adds it (Task 2).
- `.devcontainer/scripts/post-start.sh` exists and contains the same silent-skip pattern at lines 33–34 (fallback path).
- `CLAUDE.md` has no `corvia workspace` references. Only `AGENTS.md` (lines 30, 32, 33, 35) does. Design's mention of CLAUDE.md is a false positive; plan updates AGENTS.md only. (`README.md` also has stale references but is out of scope per the approved design — noted as a follow-up.)
- `corvia serve` reference in `CLAUDE.md` (Known Workarounds) is legitimate and stays.

---

### Task 1: Remove untracked stdio workaround

**Files:**
- Delete: `.devcontainer/.mcp.json` (untracked; contains stdio `corvia mcp` config)

- [ ] **Step 1: Confirm the file is untracked and contains the expected stdio config**

Run:
```bash
git status --porcelain .devcontainer/.mcp.json
cat .devcontainer/.mcp.json
```

Expected:
- `git status` prints a line beginning with `??` (untracked).
- `cat` prints a JSON object with `"type": "stdio"`, `"command": "corvia"`, `"args": ["mcp"]`.

- [ ] **Step 2: Delete the file**

Run:
```bash
rm .devcontainer/.mcp.json
```

- [ ] **Step 3: Confirm removal**

Run:
```bash
test ! -e .devcontainer/.mcp.json && echo OK
git status --porcelain .devcontainer/.mcp.json
```

Expected: `OK`, then empty output from git-status.

- [ ] **Step 4: No commit needed**

The file was never tracked. Nothing to commit from this task. Proceed to Task 2.

---

### Task 2: Add `loge` helper to `lib.sh`

**Files:**
- Modify: `.devcontainer/scripts/lib.sh` (after the `logw` function, ~line 24)

- [ ] **Step 1: Read the current log helpers**

Run:
```bash
sed -n '5,25p' .devcontainer/scripts/lib.sh
```

Expected output (the existing helpers):
```
err() { echo "Error: $*" >&2; }

# Colored [module] log output. Usage: log <module> <message>
# Colors: infra=cyan, core=green, ide=magenta, warn=yellow
log() {
    local mod="$1"; shift
    printf '\033[36m[%s]\033[0m %s\n' "$mod" "$*"
}
logg() {
    local mod="$1"; shift
    printf '\033[32m[%s]\033[0m %s\n' "$mod" "$*"
}
logm() {
    local mod="$1"; shift
    printf '\033[35m[%s]\033[0m %s\n' "$mod" "$*"
}
logw() {
    local mod="$1"; shift
    printf '\033[33m[%s]\033[0m %s\n' "$mod" "$*"
}
```

- [ ] **Step 2: Add `loge` helper after `logw`**

Use Edit tool to insert after the `logw` block. The new helper mirrors the existing style but uses red (`\033[31m`) and writes to stderr.

```bash
logw() {
    local mod="$1"; shift
    printf '\033[33m[%s]\033[0m %s\n' "$mod" "$*"
}
loge() {
    local mod="$1"; shift
    printf '\033[31m[%s]\033[0m %s\n' "$mod" "$*" >&2
}
```

- [ ] **Step 3: Smoke-test the helper**

Run:
```bash
bash -c 'source .devcontainer/scripts/lib.sh && loge services "test-error"' 2>/tmp/loge.err
cat /tmp/loge.err
```

Expected: `/tmp/loge.err` contains `[services] test-error` (with ANSI escape prefix).

- [ ] **Step 4: Shellcheck**

Run:
```bash
command -v shellcheck >/dev/null && shellcheck .devcontainer/scripts/lib.sh || echo "shellcheck unavailable — skipping"
```

Expected: no warnings, or "shellcheck unavailable" (acceptable).

- [ ] **Step 5: Commit**

Run:
```bash
git add .devcontainer/scripts/lib.sh
git commit -m "$(cat <<'EOF'
chore(devcontainer): add loge helper for error-level red+stderr logs

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Replace Taskfile silent-skip with loud failure

**Files:**
- Modify: `.devcontainer/Taskfile.yml` (task `post-start:corvia-serve`, ~lines 58–85)

**Behavior contract (new):**
1. `corvia serve --help` must succeed → else print installed tag, required minimum, remediation; exit 1.
2. If `:8020` already listening → log and exit 0 (unchanged).
3. Start in background; probe up to 5 s → if TCP never opens, exit 1 (was: warn and exit 0).

- [ ] **Step 1: Record current behavior for comparison**

Run:
```bash
sed -n '58,86p' .devcontainer/Taskfile.yml
```

Note the current block — it has two silent skips: `exit 0` after the missing-`serve` warning, and an implicit `exit 0` after the "not responding after 5s" warning (loop falls through with no failure).

- [ ] **Step 2: Verify current (broken) behavior with a stubbed corvia**

Run:
```bash
TMPDIR=$(mktemp -d)
cat > "$TMPDIR/corvia" <<'EOF'
#!/bin/bash
case "$1" in
  serve) echo "error: unrecognized subcommand 'serve'" >&2; exit 2 ;;
  *) exec /usr/local/bin/corvia "$@" ;;
esac
EOF
chmod +x "$TMPDIR/corvia"
PATH="$TMPDIR:$PATH" task -t .devcontainer/Taskfile.yml post-start:corvia-serve; echo "exit=$?"
```

Expected (current/broken): task prints the "not supported — skipping" warning and exits 0. This documents the bug.

- [ ] **Step 3: Rewrite the task block**

Use Edit to replace the existing `post-start:corvia-serve` block with the new one below. The `desc` stays the same; the `cmds:` body is fully replaced.

Old block (in `.devcontainer/Taskfile.yml`, starting with `post-start:corvia-serve:`):

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
        if bash -c ': > /dev/tcp/127.0.0.1/8020' 2>/dev/null; then
          logg services "corvia serve: already running on port 8020"
          exit 0
        fi
        # 3. Start server in background
        logg services "corvia serve: starting on port 8020"
        nohup corvia serve --port 8020 >> {{.WORKSPACE_ROOT}}/.corvia/serve.log 2>&1 &
        # 4. Health probe — wait up to 5s for TCP connection
        for i in 1 2 3 4 5; do
          sleep 1
          if bash -c ': > /dev/tcp/127.0.0.1/8020' 2>/dev/null; then
            logg services "corvia serve: ready (${i}s)"
            exit 0
          fi
        done
        logw services "corvia serve: not responding after 5s — check .corvia/serve.log"
```

New block (replace the whole block above with this):

```yaml
  post-start:corvia-serve:
    desc: "Start corvia serve (HTTP MCP server) in background"
    cmds:
      - |
        source {{.SCRIPT_DIR}}/lib.sh
        # 1. Capability guard — fail loudly if binary lacks `serve`.
        # Workspace requires HTTP MCP; stdio is deprecated here.
        if ! corvia serve --help >/dev/null 2>&1; then
          tag="$(cat /usr/local/share/corvia-release-tag 2>/dev/null || echo unknown)"
          loge services "corvia serve: not supported by installed binary (tag=$tag)"
          loge services "this workspace requires a serve-capable binary (corvia >= v1.0.1)"
          loge services "remediation: task post-create:install-binary  (or rebuild devcontainer)"
          exit 1
        fi
        # 2. Already-running check — idempotent: exit 0 if :8020 already listening.
        if bash -c ': > /dev/tcp/127.0.0.1/8020' 2>/dev/null; then
          logg services "corvia serve: already running on port 8020"
          exit 0
        fi
        # 3. Start server in background.
        logg services "corvia serve: starting on port 8020"
        nohup corvia serve --port 8020 >> {{.WORKSPACE_ROOT}}/.corvia/serve.log 2>&1 &
        # 4. Health probe — 5s budget; hard-fail if TCP never opens.
        for i in 1 2 3 4 5; do
          sleep 1
          if bash -c ': > /dev/tcp/127.0.0.1/8020' 2>/dev/null; then
            logg services "corvia serve: ready (${i}s)"
            exit 0
          fi
        done
        loge services "corvia serve: not responding after 5s — check .corvia/serve.log"
        exit 1
```

- [ ] **Step 4: Verify the new missing-`serve` path fails loudly**

Run:
```bash
TMPDIR=$(mktemp -d)
cat > "$TMPDIR/corvia" <<'EOF'
#!/bin/bash
case "$1" in
  serve) echo "error: unrecognized subcommand 'serve'" >&2; exit 2 ;;
  *) exec /usr/local/bin/corvia "$@" ;;
esac
EOF
chmod +x "$TMPDIR/corvia"
PATH="$TMPDIR:$PATH" task -t .devcontainer/Taskfile.yml post-start:corvia-serve 2>/tmp/task.err; echo "exit=$?"
cat /tmp/task.err
```

Expected:
- `exit=1`
- stderr contains: `not supported by installed binary`, `requires a serve-capable binary (corvia >= v1.0.1)`, and `remediation:`.

- [ ] **Step 5: Verify parse is clean**

Run:
```bash
task -t .devcontainer/Taskfile.yml --list 2>&1 | grep -E "post-start:corvia-serve"
```

Expected: a line showing the task with its description. No YAML parse errors above it.

- [ ] **Step 6: Commit**

Run:
```bash
git add .devcontainer/Taskfile.yml
git commit -m "$(cat <<'EOF'
fix(devcontainer): make post-start:corvia-serve fail loudly

Silent skip on missing 'corvia serve' subcommand hid the broken HTTP MCP
path from users — Claude Code started without MCP tools and nothing
visibly failed. Replace the skip with an actionable error (tag +
required minimum + remediation) and promote the TCP-probe timeout to a
hard failure so "serve started but died" also surfaces.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Apply same contract to bash fallback

**Files:**
- Modify: `.devcontainer/scripts/post-start.sh` (lines ~31–49, the "3/5 Starting corvia serve" block)

- [ ] **Step 1: Re-read the current block for exact match**

Run:
```bash
sed -n '31,49p' .devcontainer/scripts/post-start.sh
```

Expected: block starting with `# ── 3/5 ───` through the `[ "$_ready" -eq 0 ] && fail_msg ...` line.

- [ ] **Step 2: Replace the block**

Use Edit. The old block:

```bash
# ── 3/5 ───────────────────────────────────────────────────────────────
step "Starting corvia serve"
if ! corvia serve --help >/dev/null 2>&1; then
    echo "    corvia serve: not supported by installed binary — skipping"
elif bash -c ': > /dev/tcp/127.0.0.1/8020' 2>/dev/null; then
    echo "    already running on port 8020"
else
    nohup corvia serve --port 8020 >> "$WORKSPACE_ROOT/.corvia/serve.log" 2>&1 &
    _ready=0
    for i in 1 2 3 4 5; do
        sleep 1
        if bash -c ': > /dev/tcp/127.0.0.1/8020' 2>/dev/null; then
            echo "    ready (${i}s)"
            _ready=1
            break
        fi
    done
    [ "$_ready" -eq 0 ] && fail_msg "not responding after 5s — check .corvia/serve.log"
fi
```

New block:

```bash
# ── 3/5 ───────────────────────────────────────────────────────────────
step "Starting corvia serve"
if ! corvia serve --help >/dev/null 2>&1; then
    _tag="$(cat /usr/local/share/corvia-release-tag 2>/dev/null || echo unknown)"
    fail_msg "corvia serve: not supported by installed binary (tag=$_tag)"
    fail_msg "this workspace requires a serve-capable binary (corvia >= v1.0.1)"
    fail_msg "remediation: python3 .devcontainer/scripts/install_corvia.py  (or rebuild devcontainer)"
    exit 1
elif bash -c ': > /dev/tcp/127.0.0.1/8020' 2>/dev/null; then
    echo "    already running on port 8020"
else
    nohup corvia serve --port 8020 >> "$WORKSPACE_ROOT/.corvia/serve.log" 2>&1 &
    _ready=0
    for i in 1 2 3 4 5; do
        sleep 1
        if bash -c ': > /dev/tcp/127.0.0.1/8020' 2>/dev/null; then
            echo "    ready (${i}s)"
            _ready=1
            break
        fi
    done
    if [ "$_ready" -eq 0 ]; then
        fail_msg "corvia serve: not responding after 5s — check .corvia/serve.log"
        exit 1
    fi
fi
```

Note: `fail_msg` already writes to stderr (defined at line 13); the bash fallback has no `loge` in scope. Remediation points at `install_corvia.py` directly because `task` is unavailable in this code path by definition.

- [ ] **Step 3: Syntax check**

Run:
```bash
bash -n .devcontainer/scripts/post-start.sh && echo OK
command -v shellcheck >/dev/null && shellcheck .devcontainer/scripts/post-start.sh || echo "shellcheck unavailable — skipping"
```

Expected: `OK`, and no shellcheck warnings (or shellcheck unavailable).

- [ ] **Step 4: Simulate missing-serve behavior (stub)**

Run:
```bash
TMPDIR=$(mktemp -d)
cat > "$TMPDIR/corvia" <<'EOF'
#!/bin/bash
case "$1" in
  serve) echo "error: unrecognized subcommand 'serve'" >&2; exit 2 ;;
  init)  echo "stub: ok"; exit 0 ;;
  *) exec /usr/local/bin/corvia "$@" ;;
esac
EOF
chmod +x "$TMPDIR/corvia"
# Short-circuit: just execute the block of interest.
set +e
WORKSPACE_ROOT=/tmp/fakews PATH="$TMPDIR:$PATH" bash -c '
  source .devcontainer/scripts/lib.sh
  step() { printf " => %s\n" "$*"; }
  fail_msg() { printf "    ... FAILED (%s)\n" "$*" >&2; }
  set -euo pipefail
  step "Starting corvia serve"
  if ! corvia serve --help >/dev/null 2>&1; then
    _tag="$(cat /usr/local/share/corvia-release-tag 2>/dev/null || echo unknown)"
    fail_msg "corvia serve: not supported by installed binary (tag=$_tag)"
    fail_msg "this workspace requires a serve-capable binary (corvia >= v1.0.1)"
    fail_msg "remediation: python3 .devcontainer/scripts/install_corvia.py  (or rebuild devcontainer)"
    exit 1
  fi
' 2>/tmp/bash.err
echo "exit=$?"
cat /tmp/bash.err
```

Expected:
- `exit=1`
- stderr contains: `not supported by installed binary`, `requires a serve-capable binary (corvia >= v1.0.1)`, and `remediation:`.

- [ ] **Step 5: Commit**

Run:
```bash
git add .devcontainer/scripts/post-start.sh
git commit -m "$(cat <<'EOF'
fix(devcontainer): mirror loud-failure contract in bash fallback

Keep the legacy post-start.sh fallback aligned with the Taskfile: exit
non-zero with actionable remediation if the installed corvia binary
lacks 'serve', and promote TCP-probe timeout to hard failure.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Strip stale `corvia workspace` refs from AGENTS.md

**Files:**
- Modify: `AGENTS.md` (Quick Reference section; lines 28–36)

**Mapping of stale → correct:**
| Current (wrong) | Replacement |
|---|---|
| `corvia workspace status` | `corvia status` |
| `corvia search "query"` | `corvia search "query"` (unchanged, already correct) |
| `corvia workspace ingest` | `corvia ingest` |
| `corvia workspace ingest --fresh` | `corvia ingest --fresh` |
| `corvia serve &` | `corvia serve &` (unchanged, already correct) |
| `corvia workspace init-hooks` | (remove — no corresponding subcommand; not needed for HTTP flow) |

- [ ] **Step 1: Read the current block**

Run:
```bash
sed -n '26,40p' AGENTS.md
```

Expected: a fenced `bash` code block with 5 lines beginning with `corvia ...`.

- [ ] **Step 2: Replace stale lines**

Use Edit to change each exact match:

Replace `corvia workspace status          # Check workspace + service health` with `corvia status                   # Check indexed entries + recent traces`.

Replace `corvia workspace ingest          # Index all repos` with `corvia ingest                   # Index the current workspace`.

Replace `corvia workspace ingest --fresh  # Re-index from scratch` with `corvia ingest --fresh            # Re-index from scratch`.

Delete the line `corvia workspace init-hooks      # Generate doc-placement hooks from config` entirely (including its trailing newline).

- [ ] **Step 3: Verify no `corvia workspace` references remain in AGENTS.md**

Run:
```bash
grep -n "corvia workspace" AGENTS.md || echo "clean"
```

Expected: `clean`.

- [ ] **Step 4: Verify CLAUDE.md is still clean (sanity — no edit needed)**

Run:
```bash
grep -n "corvia workspace" CLAUDE.md || echo "clean"
```

Expected: `clean`.

- [ ] **Step 5: Commit**

Run:
```bash
git add AGENTS.md
git commit -m "$(cat <<'EOF'
docs(agents): fix stale 'corvia workspace' subcommand references

The corvia CLI has no 'workspace' subcommand — these references never
worked. Replace with the actual subcommands (status, ingest) and drop
the nonexistent 'init-hooks'.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Final verification

No code changes; validation only. No commit.

- [ ] **Step 1: Confirm no lingering stdio `.mcp.json` artifacts anywhere tracked**

Run:
```bash
git ls-files | xargs grep -l '"type": "stdio"' 2>/dev/null || echo "clean"
```

Expected: `clean`.

- [ ] **Step 2: Confirm root `.mcp.json` is still HTTP**

Run:
```bash
cat .mcp.json
```

Expected: JSON with `"type": "http"` and `"url": "http://127.0.0.1:8020/mcp"`.

- [ ] **Step 3: Confirm Taskfile parses**

Run:
```bash
task -t .devcontainer/Taskfile.yml --list 2>&1 | head -20
```

Expected: list of tasks including `post-start:corvia-serve` with no YAML errors.

- [ ] **Step 4: Re-run the missing-serve harness against the Taskfile (regression check)**

Run:
```bash
TMPDIR=$(mktemp -d)
cat > "$TMPDIR/corvia" <<'EOF'
#!/bin/bash
case "$1" in
  serve) echo "error: unrecognized subcommand 'serve'" >&2; exit 2 ;;
  *) exec /usr/local/bin/corvia "$@" ;;
esac
EOF
chmod +x "$TMPDIR/corvia"
PATH="$TMPDIR:$PATH" task -t .devcontainer/Taskfile.yml post-start:corvia-serve 2>/tmp/final.err; echo "exit=$?"
grep -E "v1.0.1|remediation" /tmp/final.err
```

Expected: `exit=1` and the grep prints both the `v1.0.1` line and the `remediation:` line.

- [ ] **Step 5: Report branch state**

Run:
```bash
git log --oneline origin/master..HEAD
```

Expected: 4 new commits (Task 2, 3, 4, 5) plus the design-spec commit from brainstorming.

---

## Follow-ups (out of scope for this PR)

- `README.md` contains the same stale `corvia workspace` references (lines 37, 38, 61, 67). Fix in a follow-up chore commit to keep this PR focused on the MCP access fix.
- Cut corvia `v1.0.1` release so fresh devcontainer builds pick up a serve-capable binary (tracked by maintainer).
