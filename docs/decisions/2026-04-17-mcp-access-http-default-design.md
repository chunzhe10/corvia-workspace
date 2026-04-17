# MCP access: HTTP as default, stdio deprecated

**Date:** 2026-04-17
**Status:** Approved
**Scope:** `.devcontainer/.mcp.json`, `.devcontainer/Taskfile.yml`, `.devcontainer/scripts/post-start.sh`, `.devcontainer/scripts/lib.sh`, `AGENTS.md`, `README.md`

> **Update (2026-04-17, post-review):** Corvia `v1.0.1` shipped during this work
> — it already includes the `corvia serve` subcommand (PR #115) and a
> `GET /healthz` endpoint (PR #116). Minimum required version is therefore
> `v1.0.1`, not `v1.0.2` as originally planned. The post-start probe uses `curl /healthz` instead
> of a raw TCP open for functional readiness. The `post-start:` task order
> places `corvia-serve` last so a hard-failure on a pre-v1.0.1 binary does
> not skip `claude-integration` or `sweep`.

## Problem

`.mcp.json` at the workspace root declares HTTP MCP transport at
`http://127.0.0.1:8020/mcp`. The installed/released `corvia` binary is v1.0.0,
which lacks the `corvia serve` subcommand — that subcommand landed on corvia
master **after** v1.0.0 was tagged.

The devcontainer's `post-start:corvia-serve` task has a capability guard that
runs `corvia serve --help` and, if the subcommand is missing, logs a warning and
exits 0 (silent skip). The result: no HTTP server runs, `.mcp.json` points at a
dead URL, Claude Code starts with zero corvia MCP tools, and nothing visibly
fails.

Evidence that a previous mid-fix happened: `.devcontainer/.mcp.json` (untracked)
contains a stdio-based `corvia mcp` config — a local workaround that was never
committed.

Secondary issue: `CLAUDE.md` and `AGENTS.md` reference `corvia workspace status`,
`corvia workspace ingest`, and `corvia workspace init-hooks`. No `workspace`
subcommand exists in the corvia CLI — these are stale and misleading.

## Decision

**HTTP is the default and only supported MCP transport in this workspace.**
Stdio is deprecated here. The workspace fix is the config + hardening half of
the story; the release-side half (cutting v1.0.1 with the `serve` subcommand)
is tracked separately by the maintainer.

## Design

### Changes

| File | Change |
|------|--------|
| `.devcontainer/.mcp.json` | Delete (untracked stdio workaround). |
| `.devcontainer/Taskfile.yml` (`post-start:corvia-serve`) | Replace silent-skip capability guard with loud failure: print installed release tag, required minimum (`≥ v1.0.1`), actionable remediation, exit non-zero. Also promote the 5-second TCP-probe timeout from warning to hard failure. |
| `.devcontainer/scripts/post-start.sh` | Apply the same loud-failure contract to the bash-fallback equivalent, if present. |
| `CLAUDE.md` | Remove/correct `corvia workspace ...` references. |
| `AGENTS.md` | Same — the Quick Reference section lists nonexistent `corvia workspace` commands. |

### Loud-failure contract

Current behavior in `post-start:corvia-serve`:

```bash
if ! corvia serve --help >/dev/null 2>&1; then
  logw services "corvia serve: not supported by installed binary — skipping"
  exit 0   # ← silent skip; root cause of invisible breakage
fi
```

Replacement:

```bash
if ! corvia serve --help >/dev/null 2>&1; then
  tag="$(cat /usr/local/share/corvia-release-tag 2>/dev/null || echo unknown)"
  loge services "corvia serve: not supported by installed binary (tag=$tag)"
  loge services "this workspace requires a serve-capable binary (corvia >= v1.0.1)"
  loge services "remediation: task post-create:install-binary  (or rebuild devcontainer)"
  exit 1
fi
```

If `lib.sh` has no `loge` helper, use `logw` style with redirection to stderr +
explicit `exit 1`.

The TCP-probe loop that currently only warns ("corvia serve: not responding
after 5s") becomes a hard failure: serve-started-but-dead must be visible, not
silently masqueraded as success.

### What stays the same

- `.mcp.json` at the workspace root — already HTTP, already correct.
- `.devcontainer/scripts/install_corvia.py` — "latest release" behavior is fine;
  v1.0.1 will flow in once the maintainer cuts it.
- `corvia mcp` stdio subcommand in `repos/corvia/` — out of scope; stdio is
  deprecated at the workspace level, not removed from the binary.

### Non-goals

- Dynamic `.mcp.json` rewriting at post-start.
- Installer-side minimum-version pin (would create a merge-order hazard with
  v1.0.1 tagging).
- Removing `corvia mcp` from the CLI.

## Consequences

**Positive:**
- Post-start no longer silently masks the broken MCP path. Any future
  regression in binary capability will surface immediately.
- `.mcp.json` remains deterministic and checked in.
- Workspace docs stop advertising commands that don't exist.

**Negative / accepted:**
- Until v1.0.1 is released, a fresh devcontainer rebuild will fail at post-start
  unless someone manually installs a serve-capable binary (e.g., `cargo build`
  + copy per the `CLAUDE.md` workaround). This is the intended tradeoff: loud
  failure over invisible breakage.

**Ordering:**
- This PR can merge before v1.0.1 is tagged. Users with an existing working
  devcontainer are unaffected (post-start only fails on rebuild). New
  containers built before v1.0.1 lands will see a clear error; the user cuts
  v1.0.1 and a rebuild picks it up.

## Testing

- **Config parse**: `task --dry post-start:corvia-serve` parses cleanly.
- **Missing-serve path**: place a pre-v1.0.1 binary at `/usr/local/bin/corvia`;
  run the task; assert non-zero exit, stderr contains `v1.0.1` and
  `remediation`.
- **Happy path**: build `corvia` from source (`cd repos/corvia && cargo build`);
  install; run the task; assert `:8020` responds; `curl -sS
  http://127.0.0.1:8020/mcp` returns a valid MCP response.
- **Doc grep**: `grep -rn "corvia workspace" CLAUDE.md AGENTS.md` returns
  nothing after edits.
- **E2E** (dev-loop Phase 8): fresh Claude Code session sees `corvia_search`
  and `corvia_write` tools wired through `.mcp.json`.
