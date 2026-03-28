# Multi-Spoke Phase 3: Autonomous Spokes

**Date:** 2026-03-28
**Status:** Design
**Issue:** #38
**Depends on:** #35 (Phase 0), #36 (Phase 1), #37 (Phase 2) -- all closed

---

## Goal

Spokes run fully autonomously: container starts, runs dev-loop on an issue,
reports progress, and self-destructs after completion. The hub prunes exited
containers. No human intervention required after `spoke create`.

---

## Changes

### 1. Entrypoint fixes and status reporting

**Problem:** The entrypoint uses `REPO_URL` but the provisioner sets `CORVIA_REPO_URL`.
Only failure reporting exists. No lifecycle visibility.

**Fix:**
- Normalize env vars: entrypoint reads `CORVIA_REPO_URL` (matching provisioner)
- Add `report_status()` function that writes structured status updates via MCP
- Report at lifecycle points: starting, cloning, branch-created, mcp-connected,
  claude-starting, completed, failed

### 2. Permission hardening

**Problem:** Spoke Claude Code can run any Bash command including `docker` (container escape).

**Fix:** Generate `~/.claude/settings.json` in entrypoint before starting Claude Code.
Allow-list: git, cargo, npm, gh, curl, ls, cat, mkdir, cp, rm, mv, chmod, grep, find, wc, diff, sort, head, tail, tee, echo, printf, test, true, false, sleep, date, pwd, whoami, env, which, realpath, dirname, basename.
Deny-list: docker, ssh, nc, ncat, nmap, wget (prefer curl).

### 3. Telemetry

Add `spoke.*` span constants to corvia-telemetry. Instrument SpokeProvisioner
create/destroy/prune/restart methods with structured spans.

### 4. Hub-side prune

**Problem:** Exited spoke containers accumulate.

**Fix:**
- `spoke prune` CLI command: remove exited containers older than threshold (default 1h)
- Server background task: prune every 5 minutes
- Prune only containers with `corvia.spoke=true` label in `exited` state

### 5. Hub restart resilience

- `spoke restart --all` flag to restart all running spokes after hub restart
- Document the hub restart procedure for spoke environments

### 6. Credential expiry handling

- Entrypoint validates credentials before starting Claude Code
- Document apiKeyHelper for long-running sessions
- Document credential rotation/revocation workflow

### 7. Docker stats in dashboard

- Backend: query Docker stats API for CPU% and memory per spoke
- Frontend: display resource usage in spoke cards

---

## Deferred (not in this PR)

- MCP rate limiting (per-agent-id: 60 writes/min, 300 reads/min)
- Secret content filter on corvia_write (regex for API key patterns)
- Spoke log capture via corvia-telemetry (not corvia_write)

These require deeper kernel changes and are better as separate issues.
