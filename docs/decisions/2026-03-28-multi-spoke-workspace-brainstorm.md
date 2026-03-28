# Multi-Spoke Workspace: Brainstorm

**Date:** 2026-03-28
**Status:** Design Complete (review fixes incorporated 2026-03-28)
**Scope:** corvia workspace product, devcontainer infrastructure, Claude Code integration

---

## Problem Statement

Today, running multiple Claude Code agents on separate issues requires manually
opening N independent devcontainers. Each has its own corvia server, its own
knowledge store, and its own Claude Code login. Knowledge is siloed. Decisions
made by Agent A on branch X are invisible to Agent B on branch Y until code
merges via PR and the repo is re-pulled.

**Goal:** Multiple Claude Code instances (spokes) running dev-loop on separate
issues/branches, all connected to a single shared corvia server (hub), with
pooled organizational memory. Zero manual login per spoke.

---

## Key Concerns

1. **Spoke lifecycle** -- how are spoke containers created, managed, destroyed?
2. **Auth propagation** -- Claude Code requires login; how to avoid per-container login?
3. **Knowledge coordination** -- how do agents learn from each other in real time?
4. **Dashboard visibility** -- how does the owner see what all spokes are doing?
5. **Bridging strategy** -- Claude Code teams can't span containers yet; what works now?

---

## Concern 1: Spoke Lifecycle

### Current State

Each devcontainer is fully independent: own Dockerfile, own corvia server, own
`.corvia/` data directory, own inference server. No shared state.

### Design Options

#### Option A: Docker Compose sidecar spokes

Hub is the main devcontainer (corvia server + inference). Spokes are lightweight
Docker containers defined in a compose file. `corvia workspace spoke` CLI command
manages them.

```
corvia workspace spoke create --repo corvia --issue 42
corvia workspace spoke list
corvia workspace spoke destroy spoke-42
```

Under the hood:
- Generates a Docker container from a spoke template
- Connects to hub's Docker network
- Mounts the repo (git worktree or fresh clone)
- Injects `.mcp.json` pointing to hub's corvia server
- Starts Claude Code with `/dev-loop <issue>`

**Pros:** corvia controls the full lifecycle. Clean product surface.
**Cons:** Requires Docker-in-Docker or host Docker socket access from the hub container.

#### Option B: corvia provisions, user starts Claude Code

corvia handles environment setup (container, network, repo, auth) but does not
start Claude Code itself. The user (or a shell script) starts Claude Code in each
spoke.

```
corvia workspace spoke create --repo corvia --branch feat/42-bm25
# Output: Spoke "spoke-42" ready at container "corvia-spoke-42"
#         Run: docker exec -it corvia-spoke-42 claude
```

**Pros:** Simpler. corvia doesn't need to manage Claude Code process lifecycle.
**Cons:** Extra manual step per spoke.

#### Option C: Devcontainer features (VS Code native)

Each spoke is a VS Code devcontainer using a shared Docker network. The hub is
one devcontainer; spokes are additional devcontainers opened in separate VS Code
windows. corvia doesn't manage container lifecycle at all.

**Pros:** Leverages existing VS Code devcontainer UX.
**Cons:** Manual per-spoke setup. No `corvia workspace spoke` CLI. Not automatable.

### Decision: Option A -- Product CLI

**Decided:** `corvia workspace spoke create/list/destroy` as product commands.
Docker socket access is acceptable. corvia manages the full spoke lifecycle.

---

## Concern 2: Auth Propagation (Claude Code Login)

### The Problem

Claude Code requires authentication. On Linux (containers), credentials are stored
in `~/.claude/.credentials.json`. Each new container needs either:
- Interactive `claude login` (browser OAuth flow), or
- `ANTHROPIC_API_KEY` environment variable, or
- Mounted credentials file

### Verified: `.credentials.json` Alone IS Sufficient

**Test (2026-03-28):** Spawned a fresh `node:22-bookworm` container with only
`.credentials.json` piped in. Ran `claude -p "respond with AUTHENTICATED"`.
Result: **success**. No `.claude.json` needed.

**The real issue is Docker-in-Docker mount paths.** When the hub devcontainer tries
to mount `/root/.claude/.credentials.json` into a spoke container, Docker daemon
resolves that path against the **host filesystem**, not the container filesystem.
The file doesn't exist on the host at that path (it exists inside the devcontainer's
bind mount). Docker silently creates an empty directory instead of failing.

**Solution for spokes:** Do NOT use `-v` bind mounts for credentials when running
Docker-in-Docker. Instead:
1. **Pipe credentials:** `cat .credentials.json | docker run -i ... bash -c 'cat > /root/.claude/.credentials.json'`
2. **Docker volume:** Create a named volume with the credentials, share across spokes
3. **Environment variable:** Use `ANTHROPIC_API_KEY` (avoids file mounting entirely)
4. **Docker secret:** Use Docker secrets for compose-based deployments

**Why each devcontainer asks for login:** Each devcontainer uses VS Code's mount
mechanism which correctly maps host paths. But if the host `~/.claude/` doesn't have
`.credentials.json` (e.g., never logged in on the host itself), the mount brings an
empty directory. Each container must login independently.

### Solution: Three tiers

#### Tier 1: `ANTHROPIC_API_KEY` env var (preferred for spokes)

Set once in the hub's environment or secrets manager. Injected into every spoke
container via `docker run -e ANTHROPIC_API_KEY=...` or compose env_file.

- No interactive login needed. Ever.
- Pay-as-you-go API billing (not subscription).
- Works with `claude -p` (non-interactive/headless) and interactive mode.
- Multiple concurrent instances safely share the same key.

#### Tier 2: Mounted credentials (subscription auth)

Mount **both** files from host:
```yaml
volumes:
  - ~/.claude/.credentials.json:/root/.claude/.credentials.json:ro
  - ~/.claude/.claude.json:/root/.claude/.claude.json:ro
```

- Uses existing subscription auth (Max plan = Opus access).
- Single login on host propagates to all containers.
- Read-only mount prevents spokes from corrupting auth state.
- **Requires both files** or login prompt will appear.

#### Tier 3: `apiKeyHelper` script (advanced/enterprise)

For rotating tokens (Vault, AWS STS, etc.), configure a helper script:
```json
{"apiKeyHelper": "/usr/local/bin/get-token.sh"}
```

Claude Code calls this script at startup and on 401 errors. TTL configurable via
`CLAUDE_CODE_API_KEY_HELPER_TTL_MS`.

### Decision: Credential injection for spokes

Owner has a Max subscription (Opus access, `subscriptionType: "max"`).
For spokes created by `corvia workspace spoke create`:

1. **Primary:** Pipe `.credentials.json` content into spoke at creation time
   (avoids DinD mount path issues)
2. **Fallback:** `ANTHROPIC_API_KEY` env var if piping is impractical

**Verified:** `.credentials.json` alone is sufficient for auth. No `.claude.json`
needed. Tested 2026-03-28 with fresh container.

---

## Concern 3: Knowledge Coordination via Episodic Memory

### How It Works Today

corvia's knowledge entries already carry:
- `agent_id` -- who wrote it
- `session_id` -- which work session
- `workstream` -- which branch (auto-detected from git)
- `recorded_at` / `valid_from` / `valid_to` -- temporal bounds
- `content_role` -- decision, finding, learning, etc.
- `entry_status` -- Pending / Committed / Merged

When Agent A writes a decision via `corvia_write`, it's immediately searchable by
Agent B via `corvia_search`. No git merge required. No PR needed. Real-time
knowledge pooling through the shared corvia server.

### Coordination Patterns

**Pattern 1: Implicit coordination (passive)**

Every dev-loop starts with `corvia_search` (mandated by CLAUDE.md). Agents
naturally discover what others have decided. No explicit messaging needed.

Example flow:
```
Agent A (spoke-42): corvia_write("Chose tantivy for BM25, not custom impl")
Agent B (spoke-55): corvia_search("search pipeline") -> finds Agent A's decision
Agent B: builds on that decision instead of contradicting it
```

**Pattern 2: Dependency signaling (semi-active)**

Agent A writes a "ready" signal when its work is available:
```
corvia_write:
  content_role: "finding"
  content: "BM25 endpoint ready on branch feat/42-bm25, PR #63. API: GET /api/search?q=...&mode=bm25"
```

Agent B's next `corvia_search` discovers the API is available and can integrate.

**Pattern 3: Blocking dependency (active, future)**

Not supported today. Would require a task queue in corvia where Agent B can
declare "I'm blocked on Agent A's PR #63" and get notified when it merges.
This is future work. For now, GitHub issue dependencies + human coordination
handle this case.

### What's NOT Needed

- Agent-to-agent messaging (Claude Code's job when they ship network teams)
- Process-level coordination (start/stop/kill agents)
- Shared filesystem between spokes (each has its own repo checkout)

The knowledge base IS the coordination layer. This is corvia's core value prop.

---

## Concern 4: Dashboard Enhancement

### Current Dashboard State

The dashboard already shows:
- Agent registry (all registered agents with status, activity summary)
- Live sessions (via SessionWatcher inotify on `~/.claude/sessions/`)
- Knowledge graph with clustering
- Activity feed with semantic grouping

### What's Missing for Multi-Spoke

| Feature | Description | Effort |
|---------|-------------|--------|
| **Spoke registry** | Show spoke containers: name, repo, branch, issue, status (running/stopped) | Medium |
| **Per-spoke activity** | Filter activity feed by spoke/agent | Small (workstream filter exists) |
| **Cross-spoke timeline** | Unified timeline showing all agents' decisions chronologically | Small (already works via `recorded_at`) |
| **Dependency graph** | Visual: which spokes depend on which PRs | Medium |
| **Auth status** | Show which spokes have valid auth vs expired | Small |

### Session Watcher Limitation

The current SessionWatcher monitors `~/.claude/sessions/*.jsonl` on the local
filesystem. Spokes running in separate containers write to their own `~/.claude/`
directories. Two options:

1. **Mount a shared sessions directory** -- all spokes write to a shared volume
   that the hub's SessionWatcher monitors. Simple but creates filesystem coupling.

2. **Spoke heartbeat via MCP** -- spokes periodically call `corvia_agent_status`
   (already exists). The dashboard shows agent liveness from the agent registry,
   not from session file watching. Decoupled and container-native.

**Decision:** Option 2 (MCP heartbeat). The hub should not depend on filesystem access
to spoke containers. Agent status via MCP is the right abstraction.

---

## Concern 5: Bridging Strategy

### What Claude Code Teams Would Give Us (When They Ship Network Support)

- Cross-container agent messaging
- Shared task lists with atomic claiming
- Team-level coordination (lead assigns work to teammates)
- Native multi-agent UI

### What We Have Now (Bridge)

| Claude Code Teams feature | corvia bridge equivalent |
|---------------------------|-------------------------|
| Task assignment | GitHub issues with assignees. Dev-loop checks assignees. |
| Agent messaging | `corvia_write` + `corvia_search`. Knowledge as messages. |
| Shared task list | GitHub issue board filtered by `in-progress` label |
| Team lead coordination | Human owner assigns issues, monitors dashboard |
| Status visibility | corvia dashboard (agent registry + activity feed) |

### Bridge Architecture

```
Human Owner
    │
    ├── Assigns issues on GitHub
    ├── Monitors corvia dashboard
    └── Starts/stops spokes via CLI

Hub Container (corvia server)
    │
    ├── Knowledge store (.corvia/)
    ├── Agent registry (who's active)
    ├── Dashboard (visibility)
    ├── Inference server (embeddings)
    └── MCP endpoint (0.0.0.0:8020, bearer token auth on writes)

Spoke Containers (N independent)
    │
    ├── Git repo checkout (own branch)
    ├── Claude Code instance (pinned version, non-root)
    ├── .mcp.json -> hub:8020/mcp (with auth token)
    ├── Credentials (piped at creation, not bind-mounted)
    ├── Scoped GITHUB_TOKEN (fine-grained PAT)
    ├── Per-spoke CORVIA_AGENT_ID + CORVIA_SPOKE_TOKEN
    ├── Resource limits (4GB memory, 512 cpu_shares default)
    └── Dev-loop running on assigned issue
```

### Migration Path to Claude Code Network Teams

When Claude Code ships network-based teams:
1. Spokes join a team via whatever mechanism Claude Code provides
2. corvia remains the MCP server every agent talks to (unchanged)
3. The agent-teams adapter (already designed) captures team coordination artifacts
4. Knowledge pooling continues to work exactly as before
5. Team-level messaging supplements (not replaces) knowledge-based coordination

**Key principle:** corvia is infrastructure, not orchestration. Don't build what
Claude Code will build. Build what they won't: persistent organizational memory
across teams, sessions, and time.

---

## Terminology

| Term | Definition |
|------|-----------|
| **Hub** | The primary container running corvia server, inference, and the owner's Claude Code |
| **Spoke** | A container running one Claude Code instance, working on one issue/branch, connected to the hub |
| **Workspace** | The corvia workspace (corvia.toml + repos + .corvia/ + spokes) |
| **Workstream** | A branch name. Used as a dimension on knowledge entries for filtering. |
| **Scope** | A knowledge namespace (e.g., "corvia", "user-history"). All spokes share the same scope. |

---

## Workspace as Product

### What exists today

- `corvia workspace create/init/status/ingest` (CLI commands)
- `corvia.toml` with repos, scopes, storage, embedding config
- Devcontainer integration (D52)
- Server with MCP, REST, dashboard
- Agent registry and session management

### What "workspace as product" adds

- **Spoke management**: `corvia workspace spoke create/list/destroy`
- **Network config**: Server bind address in corvia.toml (`host = "0.0.0.0"`)
- **Spoke templates**: Dockerfile + `.mcp.json` generation for spoke containers
- **Auth injection**: Spoke env setup (API key or credential mount)
- **Dashboard spoke view**: Agent registry enhanced with spoke metadata

### What stays infrastructure (not product)

- Docker runtime (docker-compose, Codespaces, DevPod, k8s)
- Host networking configuration
- VS Code devcontainer features
- CI/CD integration

### Product surface

```
corvia.toml
├── [project]           # name, scope_id (exists)
├── [storage]           # store_type, data_dir (exists)
├── [server]            # host, port (exists, add 0.0.0.0 default)
├── [embedding]         # provider, model, url (exists)
├── [[repos]]           # repo definitions (exists)
├── [[scope]]           # scope definitions (exists)
└── [workspace.spokes]  # NEW: spoke templates and defaults
    ├── image = "corvia-spoke:latest"
    ├── auth_mode = "api_key"  # or "credentials_mount"
    └── network = "corvia-net"
```

---

## Implementation Phases

### Phase 0: Foundation (blockers from 5-persona review)

1. **Verify Anthropic usage terms** for multi-container subscription credentials
2. **MCP bearer token auth** for write operations (generated at startup, injected into spokes)
3. **Pin Claude Code version** in spoke Dockerfile (never `@latest` at runtime)
4. Make server bind address configurable (`0.0.0.0` option in corvia.toml)
5. Verify concurrent MCP connections work under load

**Validates:** Security posture and legal compliance before building features.

### Phase 1: Spoke CLI (MVP)

1. `corvia workspace spoke create --repo <name> --issue <N>`
   - Creates Docker container from template
   - Attaches to corvia Docker network
   - Mounts repo (git worktree from hub's repo)
   - Injects auth (mounted subscription credentials, fallback API key)
   - Generates `.mcp.json` pointing to hub
2. `corvia workspace spoke list` -- show running spokes
3. `corvia workspace spoke destroy <name>` -- tear down

**Validates:** Can corvia manage spoke lifecycle?

### Phase 2: Dashboard Integration

1. Spoke registry in dashboard (name, repo, branch, issue, status)
2. Per-spoke activity filtering
3. Cross-spoke decision timeline
4. Agent liveness via MCP heartbeat (not filesystem)

**Validates:** Can the owner see and understand what all spokes are doing?

### Phase 3: Auto-start dev-loop

1. Spoke container auto-starts Claude Code with `/dev-loop <issue>`
2. Spoke reports progress to corvia (status updates via `corvia_write`)
3. Spoke tears down after PR is merged (or on failure after N retries)

**Validates:** Can spokes run fully autonomously?

### Phase 4: Future (when Claude Code ships network teams)

1. Integrate Claude Code team formation across spokes
2. Agent-teams adapter captures team coordination
3. Cross-spoke task dependencies via team messaging
4. corvia as the persistent memory layer for ephemeral teams

---

## Spawning Mechanism (Verified 2026-03-28)

### Proof of Concept Results

Spawned a test spoke container from inside the hub devcontainer. All components verified:

| Component | Result | Notes |
|-----------|--------|-------|
| Auth propagation | Pass | `.credentials.json` mounted via host path, Claude Code authenticated |
| Git repo | Pass | Fresh `git clone --depth 1` into spoke. Branch created. |
| Docker network | Pass | Spoke reached hub at `http://app:8020` via compose network |
| MCP connectivity | Pass | `corvia_system_status` returned 9864 entries from spoke |
| MCP search | Pass (after warmup) | Requires inference server to be loaded |

### Docker-from-Docker Architecture

This devcontainer uses Docker-from-Docker (host Docker socket mounted at
`/var/run/docker.sock`). This means:

- **Bind mounts must use HOST paths**, not container paths
- Container path `/workspaces/corvia-workspace` = host path `/home/chunzhe/corvia-project/corvia-workspace`
- Container path `/root/.claude` = host path `/home/chunzhe/.claude`
- The hub can resolve these by inspecting its own container: `docker inspect $(hostname)`

### Git: Clone beats Worktree for Spokes

**Decision change: fresh clone, not worktree.** Worktrees failed because the `.git`
file contains absolute paths to the parent repo, which don't resolve inside spoke
containers. Fresh `git clone --depth 1` is:
- Fully isolated (no path dependencies)
- Fast enough (shallow clone, few seconds)
- Works with any Docker setup (no mount path translation needed)

### Spawning Recipe (verified)

```bash
# Resolve host paths from hub container
HUB_CONTAINER=$(hostname)
HOST_CREDS=$(docker inspect $HUB_CONTAINER \
  --format '{{range .Mounts}}{{if eq .Destination "/root/.claude"}}{{.Source}}{{end}}{{end}}')

# Spawn spoke
docker run -d \
  --name corvia-spoke-${ISSUE_NUMBER} \
  --network corvia-workspace_devcontainer_default \
  -v "${HOST_CREDS}/.credentials.json:/root/.claude/.credentials.json:ro" \
  -w /workspace \
  node:22-bookworm \
  bash -c '
    apt-get update -qq && apt-get install -y -qq git >/dev/null 2>&1
    npm install -g @anthropic-ai/claude-code@latest 2>&1 | tail -3
    git clone --depth 1 --branch master https://github.com/chunzhe10/corvia.git /workspace
    git checkout -b feat/${ISSUE_NUMBER}-description

    # Write MCP config pointing to hub
    mkdir -p /workspace
    echo "{\"mcpServers\":{\"corvia\":{\"type\":\"http\",\"url\":\"http://app:8020/mcp\"}}}" \
      > /workspace/.mcp.json

    # Start Claude Code with dev-loop
    claude -p "/dev-loop ${ISSUE_NUMBER}"
  '
```

### Open: Spoke Image

The test used `node:22-bookworm` + runtime install. For production, a pre-built
spoke image with Claude Code and common tools (git, build-essential) would cut
startup time from ~45s to ~5s. This image should be part of the workspace product.

### Usage Agreement (Phase 0 Blocker)

**Elevated from "consideration" to Phase 0 blocker per PM review.**

The spawning mechanism uses one user's subscription credentials across multiple
concurrent Claude Code instances. This is the entire value prop of the feature.
If Anthropic's terms prohibit it, the feature is dead on arrival.

**Action before any implementation:**
1. Verify with Anthropic: Can one Max subscription run N concurrent `claude -p`
   sessions in containers?
2. Is `ANTHROPIC_API_KEY` (pay-per-token) the intended path for programmatic use?
3. If subscription credentials are not safe: invert auth model to API key primary.

**Technical facts:**
- `claude -p` (headless) mode is officially designed for CI/container use
- `ANTHROPIC_API_KEY` env var is documented for multi-instance container scenarios
- Multiple concurrent sessions are a supported feature of Claude Code
- Rate limits are the natural throttle for concurrent usage

---

## Resolved Open Questions (Post-Review)

1. **Auth**: `.credentials.json` alone is sufficient. Verified 2026-03-28.
2. **Spoke count**: Default resource limits (4GB/spoke). Documented recommendations
   by machine size. Docker handles hard limits.
3. **Knowledge conflict**: Accepted risk for now. Semantic contradiction detection
   is future work. Agents check corvia before deciding, which mitigates most conflicts.
4. **Worktree**: Abandoned. Fresh shallow clone instead. No cleanup needed.
5. **Spoke naming**: Auto-generated `corvia-{workspace}-spoke-{issue}-{timestamp}`.
   Includes workspace name (cross-workspace collision prevention) and timestamp
   (reuse collision prevention). Override via `--name`.

---

## Decision Record

Decisions made 2026-03-28:

- [x] **Spoke lifecycle**: Product CLI (`corvia workspace spoke create/list/destroy`)
- [x] **Auth model**: Mounted subscription credentials (both `.credentials.json` +
  `.claude.json`). `ANTHROPIC_API_KEY` as fallback.
- [x] **Session monitoring**: MCP heartbeat via `corvia_agent_status`
- [x] **Docker access**: Docker socket access from hub is acceptable
- [x] **Spoke identity**: Unique `CORVIA_AGENT_ID` per spoke (not shared owner ID)
- [x] **Repo strategy**: Fresh shallow clone (worktrees break in DinD due to absolute paths)
- [x] **Workspace as product**: Yes. `corvia workspace spoke` is a product feature.
- [x] **Term "spoke"**: Adopted

### Auth finding (verified 2026-03-28)

`.credentials.json` alone is sufficient for Claude Code auth. The login issue across
devcontainers is caused by Docker-in-Docker mount path resolution, not missing files.
Solution: pipe credentials into spoke containers at creation time instead of bind mounting.

**Test results:**
- Fresh container + `.credentials.json` piped in = AUTHENTICATED (success)
- Fresh container + no credentials = "Not logged in" (expected failure)
- Subscription type `max` confirmed in OAuth token (Opus model access)
