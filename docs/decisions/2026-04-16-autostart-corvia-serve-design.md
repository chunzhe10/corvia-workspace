# Auto-start corvia serve in devcontainer

**Date:** 2026-04-16
**Status:** Implemented
**Scope:** `.devcontainer/Taskfile.yml`, `.devcontainer/scripts/post-start.sh`, `.devcontainer/devcontainer.json`

## Problem

`.mcp.json` configures HTTP MCP transport at `http://127.0.0.1:8020/mcp`, but
`corvia serve` isn't started automatically. On fresh container start, MCP calls
fail because nothing is listening on port 8020.

## Design

Add a `post-start:corvia-serve` task that starts `corvia serve` as a background
process after `corvia-init` completes. Add the equivalent logic to the bash
fallback script.

### Post-start sequence (after this change)

```
auth → corvia-init → corvia-serve → claude-integration → ensure-extensions → sweep
```

`corvia-serve` runs after `corvia-init` (which ensures `.corvia/` and models
exist) and before `claude-integration` (so MCP is available when Claude Code
starts).

### Task logic

1. **Capability guard**: Run `corvia serve --help >/dev/null 2>&1`. If it fails
   (binary too old), log a warning and exit 0. This makes the task a no-op on
   older binaries and self-healing once the release catches up.

2. **Already-running check**: TCP connection check on port 8020
   (`bash -c 'echo > /dev/tcp/127.0.0.1/8020' 2>/dev/null`). If it connects,
   log "already running" and exit 0. This handles the reconnect case (post-start
   runs again on VS Code reconnect but the server is already up).

3. **Start**: `nohup corvia serve --port 8020 >> .corvia/serve.log 2>&1 &`.
   Output goes to `.corvia/serve.log` (gitignored, resets on container recreation).

4. **Health probe**: Retry a TCP connection check on port 8020 up to 5 times
   with 1s sleep between attempts (`bash -c 'echo > /dev/tcp/127.0.0.1/8020'`).
   TCP-level check is used because the only HTTP route is `POST /mcp` which
   expects a JSON-RPC body — a bare curl would get a 4xx even when the server
   is healthy. Log success or warning. Do not fail the post-start sequence.

### Bash fallback (post-start.sh)

Same logic inlined as a new step between the corvia health check and Claude Code
integration steps.

### devcontainer.json

Update the stale comment from "No ports to forward — corvia v2 uses stdio MCP
(no HTTP server)" to reflect the HTTP transport. No `forwardPorts` needed since
the server binds to 127.0.0.1 (container-internal only).

### Log file

Server stdout/stderr goes to `.corvia/serve.log`. This path is inside `.corvia/`
which is already gitignored. No rotation needed — server output is minimal and
the file is ephemeral (lost on container recreation).

### Error handling

| Scenario | Behavior |
|----------|----------|
| Binary lacks `serve` subcommand | Warning log, skip (exit 0) |
| Port 8020 already responding | "already running" log, skip (exit 0) |
| Server fails to start within 5s | Warning log, continue (don't block startup) |
| Redb flock contention | `corvia serve` exits with error, caught by health probe failure |

### Files changed

| File | Change |
|------|--------|
| `.devcontainer/Taskfile.yml` | Add `post-start:corvia-serve` task, add to post-start sequence |
| `.devcontainer/scripts/post-start.sh` | Add serve start step (bash fallback) |
| `.devcontainer/devcontainer.json` | Update stale comment |

### Out of scope

- Removing `post-start:ensure-extensions` (tracked in v2 devcontainer migration)
- Graceful shutdown / SIGTERM drain (separate follow-up)
- Authentication / API key support
- Port forwarding to host
