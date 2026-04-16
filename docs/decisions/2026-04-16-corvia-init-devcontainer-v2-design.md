# corvia init + devcontainer v2 design

> **Status:** Approved
> **Date:** 2026-04-16
> **Scope:** `corvia init` command, devcontainer startup scripts, MCP integration
> **Reviewed by:** Senior SWE, PM, QA, DevOps, DX (5-persona review, 2026-04-16)

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
  version              # Store schema version (see Version Semantics below)
  entries/             # Knowledge entry markdown files
  index/
    store.redb         # Vector index (redb)
    tantivy/           # BM25 full-text index
  traces.jsonl         # Operation traces
  models/              # Cached embedding model files
```

Note: the directory layout matches the existing code conventions in `config.rs`
(`data_dir.join("index/store.redb")`, `data_dir.join("index/tantivy")`).

### Version semantics

`.corvia/version` is a **store schema version**, not the binary version. It
tracks the format of entries, index layout, and config schema.

- **Written by:** `corvia init` only (not by `corvia write`, `corvia ingest`,
  or `corvia mcp`). This prevents a single write from a newer binary from
  permanently pinning the store.
- **Format:** semver string (e.g., `1.0.0`), separate from the binary version.
  The binary knows which store schema versions it supports.
- **Compatibility:** a binary declares a `min_schema` and `max_schema`. If the
  store's schema version falls outside that range, init refuses or migrates.

### `corvia init` behavior

**Fresh project (no `.corvia/`):**

1. Create `.corvia/` with default `corvia.toml`
2. Write `.corvia/version` (current store schema version)
3. Update `.gitignore` (see Gitignore Strategy below)
4. Run health checklist (see below)
5. Auto-fix everything fixable
6. Pre-download embedding models to `.corvia/models/`
7. Run initial ingest if content found
8. Print summary (see Output Format below)

**Existing project (`.corvia/` exists):**

1. Read `.corvia/version`, compare to binary's supported schema range
2. Interactive: prompt to update if schema migration needed; `--yes`: auto-migrate
3. Version mismatch handling (see Version Mismatch Behavior below)
4. Run health checklist
5. Re-index if stale (new entries since last ingest, or embedding model changed)
6. Print summary

**Config migration (v1 to v2):**

`corvia init` searches for existing config in this order:
1. `.corvia/corvia.toml` (v2 location — use as-is)
2. `corvia.toml` in project root (v1 location — adopt and migrate)

When a v1 config is found:
- Copy it to `.corvia/corvia.toml`
- Rename the original to `corvia.toml.v1-backup`
- Print: `migrated config from ./corvia.toml to .corvia/corvia.toml`

When no config is found, write defaults. Never overwrite an existing
`.corvia/corvia.toml` with defaults.

### Version mismatch behavior

| Situation | Interactive | `--yes` (devcontainer) |
|-----------|------------|----------------------|
| Store schema = binary's current | No-op | No-op |
| Store schema < binary's max (upgradable) | Prompt: "Upgrade store?" | Auto-upgrade |
| Store schema > binary's max (newer store) | Error with version numbers + upgrade instructions | **Warn and continue read-only** (never block boot) |

The `--yes` mode never exits non-zero for version mismatches. It warns and
degrades gracefully. This prevents persistent `.corvia/` volumes from bricking
devcontainer startup when images roll back.

Error message format for downgrade:
```
warning: store was created by corvia schema v2.0 but this binary supports up to v1.5.
         Some features may not work. Upgrade: brew install corvia
         Bypass: corvia init --force
```

`--force` overrides the version check with a clear data-loss warning.

### Gitignore strategy

v2 uses a **selective gitignore** approach — derived data is ignored, source-of-truth
files can optionally be tracked:

`corvia init` writes a `.corvia/.gitignore` file (inside `.corvia/`, not the
project root) with:

```gitignore
# Derived data (rebuilt by corvia init / corvia ingest)
index/
models/
traces.jsonl
version
*.lock

# Source-of-truth files are NOT ignored:
# - corvia.toml (config — share with team)
# - entries/ (knowledge — share with team)
```

This means `.corvia/corvia.toml` and `.corvia/entries/` are trackable in git if
the user wants team knowledge sharing. The user can add `.corvia/` to the project
root `.gitignore` if they want everything local.

For this workspace specifically, the existing granular `.gitignore` entries for
v1 `.corvia/` paths (hnsw, lite_store.redb, etc.) should be replaced with a
single `.corvia/` line since v2 uses different internal paths.

### Project root discovery

`corvia mcp` (and all CLI commands) walk up the directory tree to find `.corvia/`,
similar to how `git` finds `.git/`. This eliminates the fragile `PathBuf::from(".")`
assumption.

Algorithm:
1. Start from cwd (or `--base-dir` if provided)
2. Walk up parent directories looking for `.corvia/corvia.toml`
3. If found, use that directory as the project root
4. If not found after reaching filesystem root, error:
   `"No .corvia/ found. Run 'corvia init' to set up."`

The `--base-dir` flag is available on all commands for explicit override (CI,
scripts, non-standard layouts).

### Locking

`corvia init` acquires an exclusive file lock on `.corvia/.lock` before making
any modifications. This prevents corruption from concurrent `corvia init` runs
(e.g., parallel devcontainer reconnects, user running init while post-start runs).

- Lock uses `flock()` (auto-released on process exit, including SIGKILL)
- Read-only operations (`corvia search`, `corvia status`) do not acquire the lock
- `corvia mcp` write operations use redb's built-in transaction locking (redb uses
  file-level locks internally via `Database::create`)
- Partial init recovery: if `.corvia/.lock` exists but the process is dead (stale
  lock), `flock()` will succeed because the kernel released it

### Concurrent MCP sessions

Multiple `corvia mcp` processes can run simultaneously (multiple Claude Code
sessions, different AI tools):

- **Reads:** safe. Redb supports concurrent readers. Tantivy supports concurrent
  readers. Each process opens its own handles.
- **Writes:** serialized by redb's internal file lock. A write from session A
  blocks session B's write until the transaction commits (~milliseconds for a
  single entry write). No deadlock risk — redb uses a single-writer model.
- **Model loading:** each process loads its own copy of the embedding model.
  Expect ~500MB RSS per `corvia mcp` process for nomic-embed-text-v1.5 + reranker.
  With 3 concurrent sessions, budget ~1.5GB. This is acceptable for devcontainers
  (typically 16-64GB RAM) but should be documented.

Future optimization (out of scope): shared embedding service or memory-mapped
model files to deduplicate across processes.

### Health checklist

Every `corvia init` run executes this checklist. Fixable issues are auto-fixed
in `--yes` mode; unfixable issues are reported as warnings (never block boot).

| Check | What it verifies | Fix action |
|-------|-----------------|------------|
| `.corvia/corvia.toml` valid | Config parseable, embedding model specified | Warn / recreate defaults |
| `.corvia/version` compatible | Store schema in binary's supported range | Upgrade or warn (see Version Mismatch) |
| `.corvia/.gitignore` present | Internal gitignore for derived data | Create it |
| `.mcp.json` exists with correct entry | See MCP Integration below | Create/update (merge, not replace) |
| Claude Code settings | `enabledMcpjsonServers` includes `"corvia"` | Append to list (not overwrite); only if `.claude/` dir exists |
| `corvia` binary resolvable | Binary on PATH | Skip (you're already running it) |
| Embedding models present | Model files in `.corvia/models/` | Download with progress output |
| Index exists and not stale | Entry count matches indexed count | Re-ingest |

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
per session. Models are pre-downloaded by `corvia init`, so `corvia mcp` starts
in <2 seconds (model load from disk, no download).

**`.mcp.json` update rules:**
- Read existing file, parse JSON
- If file has JSON syntax errors: warn, do not overwrite
- Only modify `mcpServers.corvia` — preserve all other entries
- Check if existing entry already has correct config before writing (no-op if
  already correct, avoids unnecessary git diffs on tracked files)
- If entry exists with `type: http` (v1): update to `type: stdio`

**`settings.local.json` update rules:**
- Only create/update if `.claude/` directory exists (skip on non-Claude-Code
  environments to avoid polluting other tools' configs)
- Read existing `enabledMcpjsonServers` list, append `"corvia"` if not present
- Never overwrite the list (preserves other MCP servers)

**Model pre-download:**

`corvia init` downloads embedding models to `.corvia/models/` with a progress
indicator. `corvia mcp` loads models from this path. If models are missing,
`corvia mcp` prints a clear error and exits:

```
error: embedding model not found at .corvia/models/nomic-embed-text-v1.5/
       Run 'corvia init' to download models.
```

It does NOT attempt a silent download over stdio (user cannot see progress,
Claude Code will time out).

### MCP debugging

With no HTTP server, debugging MCP issues requires a replacement for
`curl localhost:8020/mcp`.

`corvia mcp --test` spawns the MCP server, sends a `list_tools` JSON-RPC
request over internal stdio pipes, verifies the response, and exits with a
human-readable report:

```
corvia mcp test
  config:     .corvia/corvia.toml (ok)
  models:     nomic-embed-text-v1.5 + jina-v1-turbo (loaded in 1.2s)
  tools:      4 (corvia_search, corvia_write, corvia_status, corvia_traces)
  test query: "test" -> 3 results (0.8s)
  status:     ready
```

This gives users a single command to validate their MCP setup end-to-end.

### Output format

`corvia init` prints a structured summary on completion:

```
corvia initialized (.corvia/)
  config:     .corvia/corvia.toml (defaults)
  entries:    47 (23 chunks indexed)
  model:      nomic-embed-text-v1.5 (ready)
  mcp:        .mcp.json updated (stdio)
  gitignore:  .corvia/.gitignore created

Try: corvia search "how does X work?"
```

On subsequent runs (health check), only changed items are shown:

```
corvia health check
  config:     ok
  index:      ok (47 entries, 23 chunks)
  model:      ok
  mcp:        ok
  all checks passed
```

`corvia init --json` outputs machine-readable JSON for scripts and CI:

```json
{
  "status": "ok",
  "checks": {
    "config": "ok",
    "index": {"status": "ok", "entries": 47, "chunks": 23},
    "model": "ok",
    "mcp": "ok"
  }
}
```

### Binary installation

v2 ships a **single binary**: `corvia`. No adapters, no inference server.

Installation is handled by a standalone Python script in
`.devcontainer/scripts/` (not bash — bash proved fragile for download/version
logic). Uses only stdlib (`urllib`, `json`, `subprocess`). No `corvia_dev`
Python package dependency.

Steps:
1. Check `corvia --version` if on PATH
2. Fetch latest release tag via `gh release list` or GitHub API
3. If not installed or outdated: download `corvia-cli-linux-{arch}` asset
4. Verify SHA256 checksum (release must publish `.sha256` sidecar files)
5. Install to `/usr/local/bin/corvia`
6. Write release tag to `/usr/local/share/corvia-release-tag`

**Offline / rate-limited fallback:**
- If network unavailable and binary exists on PATH: skip update, warn
- If network unavailable and no binary: error with instructions
- If GitHub API rate-limited: fall back to `gh release list` (uses auth token)

**Air-gapped environments:** `corvia init --model-path /path/to/models` propagates
to `corvia.toml` as `embedding.model_path` (field already exists in config).
`corvia mcp` reads this from config. No network needed after initial setup.

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

#### `devcontainer.json`

Remove `forwardPorts: [8020, 8021, 8030]` — no HTTP server, no Vite dev server,
no inference gRPC. Update comments accordingly.

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

Cleanup: actively delete stale files from previous runs:
- `.devcontainer/.port-manifest.json`
- `.devcontainer/.env` (if it only contains `COMPOSE_PROFILES`)

This prevents stale `.env` with `COMPOSE_PROFILES=ollama` from causing Docker
Compose to look for a removed ollama service.

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
- `install_extension` (download from GitHub — can use install_vsix_direct instead)

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

Note: `setup_wrapper.py` re-runs post-start after `git pull` (appends git HEAD
to boot_id). This is fine because `corvia init --yes` is idempotent and fast
(~2s when everything is healthy). Re-indexing only triggers when entry count
differs from indexed count, not on every git commit.

#### `setup_telemetry.py`

The `init` and `record` commands write to local JSON files and are unaffected.
The `ingest` command calls the HTTP MCP endpoint, which no longer exists.

**Resolution:** Replace the HTTP MCP call in `_mcp_write()` with a `corvia write`
CLI subprocess call. The CLI is always available after `corvia init`. This is a
one-line change in the transport layer.

Alternatively, if telemetry ingestion is not valuable in v2 (most telemetry was
about the v1 process manager), remove the `ingest` and `check-ingested` steps
from the Taskfile and simplify `setup_telemetry.py` to local logging only.

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

### Release workflow

The release workflow (`repos/corvia/.github/workflows/release.yml`) currently
builds `corvia-cli`, `corvia-inference`, `corvia-adapter-basic`, and
`corvia-adapter-git`. The latter three crates no longer exist in v2.

**This must be updated before tagging the first v2 release**, or CI will fail.
The updated workflow should:
- Build only `corvia-cli`
- Publish a single binary asset: `corvia-cli-linux-amd64`
- Publish a SHA256 checksum sidecar: `corvia-cli-linux-amd64.sha256`
- Remove ORT shared library assets (embedding is in-process via static linking)

### Out of scope

- AGENTS.md / CLAUDE.md updates to reflect new tool names and workflow — separate task
- `corvia init --dry-run` / `--check` mode for CI — desirable but not required for v1 of init
- Dashboard replacement — v2 has no dashboard; status is available via `corvia status` CLI
- Multi-platform release (macOS, Windows) — Linux-only for now, matching devcontainer target
