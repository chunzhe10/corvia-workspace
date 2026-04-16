# corvia init + devcontainer v2 design

> **Status:** Approved
> **Date:** 2026-04-16
> **Scope:** `corvia init` command, devcontainer startup scripts, MCP integration

## Context

corvia v2 is a ground-up rebuild (2 crates, single binary) that replaces v1's
multi-process architecture (HTTP server, gRPC inference, adapters, Python process
manager) with an all-in-one CLI + stdio MCP server with in-process embedding.

The devcontainer startup scripts still reference v1 infrastructure that no longer
exists: `corvia-dev` (Python process manager), `tools/corvia-dashboard`,
`corvia-inference`, adapter binaries, HTTP port polling, and `corvia.toml` at the
workspace root. All of this is dead code after the v2 rebuild.

This design replaces the broken scripts and introduces `corvia init` as the
universal setup + health check command.

## Decision

### `corvia init` is the single entry point

One command handles all three user personas:
- **Developer** adding corvia to an existing project
- **Workspace operator** setting up multi-repo memory
- **AI tool integrator** wanting MCP tools in Claude Code / Copilot

### Two modes

| Mode | Trigger | Behavior |
|------|---------|----------|
| Interactive | TTY detected (default) | Prompts on decisions (update? re-index?) |
| Non-interactive | `--yes` flag or no TTY | Auto-accepts safe defaults, never blocks |

Devcontainer scripts always use `corvia init --yes`.

### `.corvia/` directory layout

Config lives inside `.corvia/`, not at the project root. Single directory to
gitignore; clean project root.

```
.corvia/
  corvia.toml          # Config (embedding model, chunking, search params)
  version              # Store format version (semver of binary that last touched it)
  entries/             # Knowledge entry JSON files
  redb/                # Vector index
  tantivy/             # BM25 full-text index
  traces.jsonl         # Operation traces
```

### `corvia init` behavior

**Fresh project (no `.corvia/`):**

1. Create `.corvia/` with default `corvia.toml`
2. Write `.corvia/version` (current binary semver)
3. Append `.corvia/` to `.gitignore` if not present
4. Run health checklist (see below)
5. Auto-fix everything fixable
6. Run initial ingest if content found
7. Print summary

**Existing project (`.corvia/` exists):**

1. Read `.corvia/version`, compare to binary version
2. Interactive: prompt to update if version mismatch; `--yes`: auto-update
3. Refuse to downgrade (older binary, newer store)
4. Run health checklist
5. Re-index if stale (new entries since last ingest, or embedding model changed)
6. Print summary

### Health checklist

Every `corvia init` run executes this checklist. Fixable issues are auto-fixed
in `--yes` mode; unfixable issues are reported.

| Check | What it verifies | Fix action |
|-------|-----------------|------------|
| `.corvia/corvia.toml` valid | Config parseable, embedding model specified | Warn / recreate defaults |
| `.corvia/version` matches binary | Store version compatible | Update store |
| `.gitignore` includes `.corvia/` | Entry present | Append it |
| `.mcp.json` exists | File present in project root | Create it |
| `.mcp.json` corvia entry correct | `type: stdio`, `command: corvia`, `args: ["mcp"]`, `cwd` correct | Update entry |
| `settings.local.json` | `enabledMcpjsonServers` includes `"corvia"` | Create/update |
| `corvia` binary resolvable | Command in MCP entry exists on PATH | Warn (can't auto-fix) |
| Embedding model loadable | Model files present or downloadable | Download |
| Index exists and not stale | Entries match indexed count | Re-ingest |

### MCP integration

v2 uses stdio MCP (not HTTP). `.mcp.json` changes from:

```json
{
  "mcpServers": {
    "corvia": {
      "type": "http",
      "url": "http://127.0.0.1:8020/mcp"
    }
  }
}
```

to:

```json
{
  "mcpServers": {
    "corvia": {
      "type": "stdio",
      "command": "corvia",
      "args": ["mcp"]
    }
  }
}
```

No server process to manage. Claude Code spawns `corvia mcp` as a child process
per session.

### Binary installation

v2 ships a **single binary**: `corvia`. No adapters, no inference server.

Installation is handled by a standalone Python script in
`.devcontainer/scripts/` (not bash -- bash proved fragile for download/version
logic). Uses only stdlib (`urllib`, `json`, `subprocess`). No `corvia_dev`
Python package dependency.

Steps:
1. Check `corvia --version` if on PATH
2. Fetch latest release tag via `gh release list` or GitHub API
3. Download `corvia-cli-linux-{arch}` if not installed or outdated
4. Install to `/usr/local/bin/corvia`
5. Write release tag to `/usr/local/share/corvia-release-tag`

### Devcontainer scripts

#### `post-create.sh` (~30 lines)

1. Wait for network
2. Forward GitHub credentials
3. Install `corvia` binary (Python script)
4. `corvia init --yes`
5. Install VS Code extension
6. Install superpowers plugin

#### `post-start.sh` (~20 lines)

1. Forward host auth (gh + claude)
2. `corvia init --yes` (idempotent health check + catch-up)
3. Install superpowers plugin (if missing)
4. Sweep cargo cache

#### `init-host.sh` (GPU + Docker only)

Keeps:
- GPU detection (NVIDIA, DRI, DXG)
- Docker compose override generation (device passthrough, group_add, cap_add)
- Stale container cleanup
- CDI spec regeneration
- gh token extraction into hosts.yml

Removes:
- All port allocation (API, Vite, inference, Ollama)
- Port manifest (`.port-manifest.json`)
- Ollama sidecar GPU passthrough
- Compose profiles / `.env` generation

#### `lib.sh` (trimmed)

Keeps:
- `forward_gh_auth`, `forward_claude_auth`, `forward_host_auth`
- `install_claude_plugin`, `install_vsix_direct`
- `retry`, `spin`, `wait_for_network`
- `detect_arch`

Removes:
- `_corvia_dev_python`, `_ensure_corvia_dev` (corvia-dev gone)
- `ensure_corvia`, `ensure_tooling` (replaced by Python install script + `corvia init`)
- `ensure_ort_provider_libs` (embedding is in-process now)
- `install_binaries` (moved to Python script)
- `install_python_editable` (no Python packages to install)
- `install_extension` (download from GitHub -- can use install_vsix_direct instead)

#### `Taskfile.yml`

Mirrors simplified post-create/post-start. Removes all service management tasks:
- `post-start:start-manager`, `post-start:wait-mcp`
- `post-start:dashboard-deps`, `post-start:wait-dashboard`
- `post-start:check-index`
- `post-start:ensure-tooling`
- `post-start:ort-providers`
- `post-create:tooling`

#### `setup_wrapper.py`

Unchanged. Still handles flock + boot-id + Taskfile delegation.

#### `setup_telemetry.py`

Needs review. Currently ingests telemetry via HTTP API (`localhost:8020`).
With no HTTP server, this either uses `corvia write` CLI or is deferred
until `corvia init` wires up the store.

#### `sweep-cargo-cache.sh`

Unchanged.

### What this eliminates

| v1 component | Status |
|-------------|--------|
| `corvia-dev` (Python process manager) | Removed entirely |
| HTTP server management | No server; stdio MCP |
| Port polling / waiting | Nothing to wait for |
| Dashboard | No HTTP server to host it |
| `corvia-inference` (gRPC) | Embedding is in-process |
| Adapter binaries | Removed from v2 |
| ORT provider library management | corvia handles model loading |
| `tools/` directory | Already deleted |
| `corvia.toml` at workspace root | Config moves to `.corvia/corvia.toml` |

### Out of scope

- `release.yml` update (currently builds non-existent crates) -- separate task
- `repos/corvia/corvia.toml` migration to `.corvia/corvia.toml` -- handled by
  `corvia init` code changes in the Rust binary
- AGENTS.md / CLAUDE.md updates to reflect new tool names and workflow -- separate task
