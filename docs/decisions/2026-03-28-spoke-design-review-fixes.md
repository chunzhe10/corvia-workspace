# Multi-Spoke Design: Review Fixes

**Date:** 2026-03-28
**Status:** INCORPORATED -- All fixes merged into main design docs (2026-03-28).
This document retained as review audit trail.
**Applies to:** All three spoke design documents

---

## Phase 0 Blockers

### C7: MCP Authentication (Security)

**Problem:** MCP endpoint on `0.0.0.0:8020` has zero authentication.

**Fix: Bearer token auth for MCP writes.**

On server startup, generate a random token and write it to `.corvia/mcp-token`:

```rust
// In corvia-server startup
let token = if config.server.host == "0.0.0.0" {
    let token = uuid::Uuid::new_v4().to_string();
    std::fs::write(data_dir.join("mcp-token"), &token)?;
    Some(token)
} else {
    // Loopback-only: no token needed (backward compatible)
    None
};
```

MCP middleware checks `Authorization: Bearer <token>` on all write operations
(corvia_write, corvia_gc_run, corvia_config_set, corvia_rebuild_index,
corvia_agent_suspend, corvia_merge_retry). Read operations (corvia_search,
corvia_ask, corvia_context, corvia_system_status) remain unauthenticated for
dashboard and debugging access.

Spoke creation injects the token:

```rust
env.push(format!("CORVIA_MCP_TOKEN={}", token));
```

Spoke `.mcp.json` includes auth header:

```json
{
  "mcpServers": {
    "corvia": {
      "type": "http",
      "url": "http://app:8020/mcp",
      "headers": {
        "Authorization": "Bearer ${CORVIA_MCP_TOKEN}"
      }
    }
  }
}
```

**Scope:** Read-only operations stay open. Write operations require token. This
preserves dashboard access while protecting data integrity.

---

### I9: Usage Agreement (PM)

**Elevated to Phase 0 blocker.**

Before any implementation, verify with Anthropic:
1. Can one Max subscription run N concurrent `claude -p` sessions in containers?
2. Is mounting `.credentials.json` into automated containers within terms?
3. Is `ANTHROPIC_API_KEY` the intended path for multi-instance container use?

**If subscription credentials are not safe:** Invert the auth model. Make
`ANTHROPIC_API_KEY` the primary auth mode, subscription credentials the fallback.
Update all docs accordingly.

**Action:** File this as a standalone investigation before implementation begins.

---

### I4: Supply Chain Pinning (Security)

**Problem:** `npm install @anthropic-ai/claude-code@latest` with no integrity check.

**Fix:**

Pre-built Dockerfile pins version:
```dockerfile
ARG CLAUDE_CODE_VERSION=2.1.86
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}
```

Runtime entrypoint never installs. If Claude Code is not present, error:
```bash
if ! command -v claude &>/dev/null; then
    echo "ERROR: Claude Code not installed. Use pre-built spoke image."
    exit 1
fi
```

The `corvia workspace spoke build-image` command handles version updates:
```bash
corvia workspace spoke build-image --claude-version 2.1.86
```

Minimal spoke image (node:22 + runtime install) retained only for development
with an explicit `--allow-runtime-install` flag and a warning.

---

## Phase 1 Blockers

### C1: HubContext Error Handling (SWE)

**Problem:** `host_path().unwrap()` panics.

**Fix:** All callers use `?` with contextual errors:

```rust
impl HubContext {
    pub fn host_path_or_err(&self, container_path: &str) -> Result<String> {
        self.host_path(container_path).ok_or_else(|| {
            let mounts: Vec<_> = self.host_mounts.keys().collect();
            CorviaError::Config(format!(
                "Cannot resolve host path for '{}'. \
                 Hub mount table: {:?}. \
                 Ensure the devcontainer mounts cover this path.",
                container_path, mounts
            ))
        })
    }
}
```

All spoke creation code uses `host_path_or_err()` instead of `host_path().unwrap()`.

---

### C2: Duplicate Spoke Name Guard (SWE)

**Fix:**

```rust
// Before create_container:
let existing = docker.list_containers(Some(
    ListContainersOptionsBuilder::new()
        .all(true)  // include stopped
        .filters(&HashMap::from([
            ("name".into(), vec![spoke_name.clone()]),
        ]))
        .build()
)).await?;

if let Some(container) = existing.first() {
    let state = container.state.as_deref().unwrap_or("unknown");
    if state == "running" {
        return Err(CorviaError::Config(format!(
            "Spoke '{}' is already running. Use `spoke destroy {}` first.",
            spoke_name, spoke_name
        )));
    }
    if force {
        docker.remove_container(&spoke_name, None).await?;
    } else {
        return Err(CorviaError::Config(format!(
            "Spoke '{}' exists (state: {}). Use --force to replace.",
            spoke_name, state
        )));
    }
}
```

Add `--force` flag to `spoke create`.

---

### C5: Container Detection (DevOps)

**Fix:**

```rust
impl HubContext {
    pub async fn detect(docker: &Docker) -> Result<Self> {
        // Check if we're in a container
        let in_container = std::path::Path::new("/.dockerenv").exists()
            || std::fs::read_to_string("/proc/1/cgroup")
                .map(|s| s.contains("docker") || s.contains("containerd"))
                .unwrap_or(false);

        if !in_container {
            return Err(CorviaError::Config(
                "Spoke management requires running inside a Docker container \
                 with the host Docker socket mounted. \
                 Run `corvia workspace spoke check` to diagnose.".into()
            ));
        }

        // ... existing detect logic
    }
}
```

Add `corvia workspace spoke check` command that validates:
- Docker socket accessible
- Running inside a container
- Network detected
- Credentials file exists
- GITHUB_TOKEN set

---

### C6: Network Selection (DevOps, SWE)

**Fix:**

```rust
fn select_network(
    networks: &HashMap<String, NetworkSettings>,
    config_override: Option<&str>,
) -> Result<String> {
    // 1. Config override takes priority
    if let Some(net) = config_override {
        if networks.contains_key(net) {
            return Ok(net.to_string());
        }
        return Err(CorviaError::Config(format!(
            "Configured network '{}' not found. Available: {:?}",
            net, networks.keys().collect::<Vec<_>>()
        )));
    }

    // 2. Filter out system networks
    let candidates: Vec<_> = networks.keys()
        .filter(|n| !matches!(n.as_str(), "bridge" | "host" | "none"))
        .collect();

    match candidates.len() {
        0 => Err(CorviaError::Config(
            "Hub is not on any user-defined Docker network. \
             Spokes need a shared network.".into()
        )),
        1 => Ok(candidates[0].clone()),
        _ => {
            // Prefer network containing "devcontainer"
            if let Some(net) = candidates.iter().find(|n| n.contains("devcontainer")) {
                return Ok(net.to_string());
            }
            Err(CorviaError::Config(format!(
                "Hub is on multiple networks: {:?}. \
                 Set [workspace.spokes] network in corvia.toml.",
                candidates
            )))
        }
    }
}
```

---

### C8: Failure UX (PM)

**Fix: Three-layer failure detection.**

**Layer 1: Pre-flight validation in `spoke create`**

Before creating any container, validate:
```rust
fn preflight_checks(config: &CorviaConfig, hub: &HubContext) -> Result<()> {
    // Docker socket
    Docker::connect_with_local_defaults()
        .map_err(|_| CorviaError::Config("Docker socket not accessible"))?;

    // Credentials
    let creds = hub.host_path_or_err("/root/.claude/.credentials.json")?;
    // (existence checked via Docker, not local fs)

    // GITHUB_TOKEN
    if std::env::var("GITHUB_TOKEN").unwrap_or_default().is_empty() {
        eprintln!("Warning: GITHUB_TOKEN not set. Spoke cannot push or create PRs.");
    }

    // Network
    // (already validated in select_network)

    // Disk space (warn if < 4GB free)
    // (best-effort check via `df`)

    Ok(())
}
```

**Layer 2: Startup health gate in entrypoint**

```bash
# After clone, before starting Claude Code:
echo "Checking MCP connectivity..."
for i in $(seq 1 10); do
    if curl -sf "${CORVIA_MCP_URL%/mcp}/api/dashboard/status" >/dev/null 2>&1; then
        echo "Hub MCP reachable."
        break
    fi
    if [ "$i" -eq 10 ]; then
        echo "ERROR: Cannot reach hub at ${CORVIA_MCP_URL}. Spoke exiting."
        # Report failure to corvia (best-effort, may fail if MCP unreachable)
        report_failure "Hub MCP unreachable after 10 retries"
        exit 1
    fi
    sleep 3
done
```

**Layer 3: `spoke list` shows failure reason**

```
NAME          REPO    BRANCH              ISSUE  STATUS    REASON
spoke-42      corvia  feat/42-bm25        #42    running   -
spoke-55      corvia  feat/55-graph-viz   #55    exited    Clone failed (exit 128)
spoke-61      corvia  feat/61-auth        #61    exited    MCP unreachable
```

Extract exit code and last log line from Docker inspect/logs.

---

### I1: GITHUB_TOKEN Validation (SWE, QA, DevOps)

**Fix:** Validate at creation time. Warn, don't block (some workflows are read-only).

```rust
let github_token = std::env::var("GITHUB_TOKEN").unwrap_or_default();
if github_token.is_empty() {
    eprintln!("Warning: GITHUB_TOKEN not set. Spoke will not be able to push or create PRs.");
    eprintln!("  Set GITHUB_TOKEN in your environment or pass --no-github to suppress.");
    if !no_github {
        return Err(CorviaError::Config(
            "GITHUB_TOKEN required for spoke operations. Use --no-github to skip.".into()
        ));
    }
}
```

---

### I2: Resource Limits (PM, QA, DevOps)

**Fix:** Default limits in SpokeConfig, override via CLI.

```rust
#[derive(Debug, Deserialize, Serialize, Clone)]
pub struct SpokeConfig {
    pub image: Option<String>,
    pub network: Option<String>,
    pub auth_mode: Option<SpokeAuthMode>,
    #[serde(default = "default_memory_limit")]
    pub memory_limit: String,        // "4g"
    #[serde(default = "default_cpu_shares")]
    pub cpu_shares: u32,             // 512
}

fn default_memory_limit() -> String { "4g".into() }
fn default_cpu_shares() -> u32 { 512 }
```

Applied to container HostConfig:
```rust
host_config: Some(HostConfig {
    memory: Some(parse_memory_limit(&spoke_config.memory_limit)),
    cpu_shares: Some(spoke_config.cpu_shares as i64),
    // Log rotation
    log_config: Some(LogConfig {
        typ: Some("json-file".into()),
        config: Some(HashMap::from([
            ("max-size".into(), "50m".into()),
            ("max-file".into(), "3".into()),
        ])),
    }),
    ..Default::default()
}),
```

CLI override: `--memory 8g --cpus 2`

Document recommended limits:
```
8GB host:  2 spokes (4GB each)
16GB host: 4 spokes (4GB each)
32GB host: 8 spokes (4GB each)
```

---

### I3: Agent Identity Auth (Security)

**Fix:** Per-spoke auth token generated at creation, validated on MCP writes.

```rust
// At spoke creation:
let spoke_token = uuid::Uuid::new_v4().to_string();

// Register in corvia agent registry with token hash
coordinator.register_spoke_agent(
    &agent_id,
    &bcrypt::hash(&spoke_token)?,
)?;

// Inject into spoke:
env.push(format!("CORVIA_SPOKE_TOKEN={}", spoke_token));
```

MCP server validates on writes:
```rust
fn validate_agent_write(agent_id: &str, token: &str, registry: &AgentRegistry) -> Result<()> {
    let record = registry.get(agent_id)?
        .ok_or(CorviaError::Agent("Unknown agent"))?;
    if !bcrypt::verify(token, &record.token_hash)? {
        return Err(CorviaError::Agent("Invalid agent token"));
    }
    Ok(())
}
```

Agent identity is no longer self-declared. It's cryptographically bound.

---

### I5: Scoped GITHUB_TOKEN (Security)

**Fix:** Document minimum required scopes. Recommend fine-grained PAT.

```
Required GitHub token permissions for spokes:
  - contents: write  (git push to feature branches)
  - pull_requests: write  (create PRs)
  - issues: write  (update issue labels/assignees)
  - metadata: read  (repo info)

Do NOT use classic PATs with `repo` scope. Use fine-grained personal access
tokens scoped to the specific repository.
```

Add validation in spoke create:
```rust
// Best-effort scope check via GitHub API
if let Ok(scopes) = check_github_token_scopes(&github_token).await {
    if scopes.contains("repo") {
        eprintln!("Warning: GITHUB_TOKEN has broad 'repo' scope. \
                   Consider using a fine-grained PAT for spokes.");
    }
}
```

---

### I6: Test Plan (QA)

**Added to spoke CLI design.**

#### Unit Tests
- `HubContext::host_path` with various mount configs (nested, overlapping, no match)
- `HubContext::detect` container detection (mock /proc/1/cgroup)
- `select_network` with 0, 1, N networks
- `SpokeConfig` deserialization (defaults, overrides, missing fields)
- Spoke name generation (from issue, from branch, collision detection)
- `preflight_checks` with missing token, missing credentials, no Docker

#### Integration Tests (require Docker)
- Spoke create/list/destroy lifecycle
- Duplicate name handling (with and without --force)
- Network resolution on actual compose network
- Credential mount verification
- Resource limits applied correctly
- Log rotation config applied

#### E2E Tests
- Spoke creates, connects to hub MCP, writes knowledge, visible on dashboard
- Spoke runs dev-loop on a test issue, creates PR
- Hub restart during spoke operation (verify MCP reconnect behavior)
- Spoke exits after completion, auto-prune removes container

#### Platform Matrix
- Linux (primary, Codespaces)
- macOS Docker Desktop (document limitations)
- WSL2 (document Docker socket path)

#### Negative Tests
- Docker daemon down
- Invalid repo name in corvia.toml
- Missing credentials file
- Expired OAuth token
- Network unreachable between spoke and hub
- Disk full during clone
- OOM during spoke operation

---

### I7: Startup Error Reporting (SWE, QA)

**Fix:** Trap handler in entrypoint.

```bash
#!/bin/bash
set -euo pipefail

# Error reporting function
report_failure() {
    local msg="$1"
    echo "SPOKE FAILURE: ${msg}"
    # Best-effort write to corvia
    curl -sf -X POST "${CORVIA_MCP_URL}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${CORVIA_MCP_TOKEN:-}" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",
             \"params\":{\"name\":\"corvia_write\",\"arguments\":{
               \"scope_id\":\"corvia\",\"agent_id\":\"${CORVIA_AGENT_ID}\",
               \"content_role\":\"finding\",\"source_origin\":\"workspace\",
               \"content\":\"Spoke ${CORVIA_AGENT_ID} failed: ${msg}\"
             }}}" 2>/dev/null || true
}

# Trap on any error
trap 'report_failure "Entrypoint failed at line $LINENO (exit $?)"' ERR

# ... rest of entrypoint
```

---

### I8 + I10: Clone Depth and Branch Naming (SWE, PM, QA)

**Fix:** Standardize on `--depth 100`. Query default branch dynamically.

```bash
# Query default branch (requires GITHUB_TOKEN)
DEFAULT_BRANCH=$(gh api "repos/${REPO_OWNER}/${REPO_NAME}" --jq '.default_branch' 2>/dev/null || echo "master")

# Clone
git clone --depth 100 --branch "${DEFAULT_BRANCH}" "${REPO_URL}" /workspace
cd /workspace

# Branch naming from issue
if [ -n "${CORVIA_ISSUE}" ]; then
    # Get issue title for branch name
    ISSUE_TITLE=$(gh issue view "${CORVIA_ISSUE}" --json title --jq '.title' 2>/dev/null || echo "")
    SLUG=$(echo "${ISSUE_TITLE}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | head -c 40)
    BRANCH="feat/${CORVIA_ISSUE}-${SLUG}"

    # Check if branch exists on remote
    if git ls-remote --heads origin "${BRANCH}" | grep -q .; then
        git fetch origin "${BRANCH}" && git checkout "${BRANCH}"
    else
        git checkout -b "${BRANCH}"
    fi
else
    git checkout -b "${CORVIA_BRANCH}"
fi
```

---

### I11: Hub Restart Resilience (DevOps)

**Fix:** MCP health check with retry in entrypoint, plus documentation.

```bash
# Health check with retry (used before starting claude AND periodically)
wait_for_hub() {
    local max_retries=${1:-30}
    for i in $(seq 1 $max_retries); do
        if curl -sf "${CORVIA_MCP_URL%/mcp}/api/dashboard/status" >/dev/null 2>&1; then
            return 0
        fi
        echo "Waiting for hub MCP... (attempt $i/$max_retries)"
        sleep 5
    done
    return 1
}

# Before starting Claude Code:
if ! wait_for_hub 30; then
    report_failure "Hub MCP unreachable after 150s"
    exit 1
fi
```

**Documentation note:** "Hub restarts (e.g., `corvia-dev down && up`) will
interrupt active MCP connections in spokes. Claude Code's MCP client will retry
on the next tool call. If the hub is down for more than 30 seconds, in-flight
dev-loop operations may fail. Use `corvia workspace spoke restart --all` after
a hub restart to recover."

---

### I12: Disk Exhaustion (DevOps)

**Fix:** Document and warn.

```rust
// In preflight_checks:
fn check_disk_space() -> Result<()> {
    let output = std::process::Command::new("df")
        .args(["-BG", "--output=avail", "/"])
        .output()?;
    let avail_gb: u64 = String::from_utf8_lossy(&output.stdout)
        .lines().nth(1)
        .and_then(|s| s.trim().trim_end_matches('G').parse().ok())
        .unwrap_or(0);

    if avail_gb < 4 {
        return Err(CorviaError::Config(format!(
            "Only {}GB disk space available. Spokes need ~2GB each for clone + build.",
            avail_gb
        )));
    }
    if avail_gb < 10 {
        eprintln!("Warning: Only {}GB disk space available. Each spoke uses ~2GB.", avail_gb);
    }
    Ok(())
}
```

---

### I13: Spoke Permissions (Security)

**Fix:** Restrict Bash to needed commands. Block dangerous patterns.

```json
{
  "permissions": {
    "allow": [
      "Bash(git *)",
      "Bash(cargo *)",
      "Bash(npm *)",
      "Bash(gh *)",
      "Bash(curl *)",
      "Bash(ls *)",
      "Bash(cat *)",
      "Bash(mkdir *)",
      "Bash(cp *)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "Glob(*)",
      "Grep(*)",
      "Agent(*)",
      "mcp__corvia__*"
    ],
    "deny": [
      "Bash(docker *)",
      "Bash(ssh *)",
      "Bash(nc *)",
      "Bash(ncat *)",
      "Bash(rm -rf /)"
    ]
  }
}
```

Note: Claude Code's permission system may not support deny lists. If not,
the allow list above is restrictive enough. The key exclusion is `docker` to
prevent container escape.

---

## Low Issues

### L1: Cache Docker Client in AppState (SWE)

```rust
// In AppState:
pub struct AppState {
    // ... existing fields
    pub docker: Option<Docker>,  // None if Docker unavailable
}

// At server startup:
let docker = Docker::connect_with_local_defaults().ok();
```

### L2: SpokeConfig Helper (SWE)

```rust
impl CorviaConfig {
    pub fn spoke_config(&self) -> SpokeConfig {
        self.workspace.as_ref()
            .and_then(|w| w.spokes.clone())
            .unwrap_or_default()
    }
}
```

### L3: Label Key Consistency (SWE)

Standardize labels. Spoke name comes from container name, not label:

```rust
// Labels (set in spoke create):
"corvia.spoke" = "true"
"corvia.workspace" = config.project.name
"corvia.repo" = repo_name
"corvia.issue" = issue_number
"corvia.branch" = branch_name
"corvia.agent_id" = agent_id

// In dashboard handler, name comes from Docker container name:
name: container.names.first().map(|n| n.trim_start_matches('/')).unwrap_or("unknown")
```

### L4: Reconcile Credential Mounting (SWE)

The brainstorm warning about DinD bind mounts is correct for raw Docker paths.
`HubContext` solves this by translating to host paths. Update brainstorm:

> "Do NOT use container paths directly for `-v` bind mounts in Docker-from-Docker.
> Use `HubContext::host_path_or_err()` to translate container paths to host paths
> before mounting."

### L5: AGENTS.md Mount Fallback (QA)

If `host_path_or_err()` fails for AGENTS.md (e.g., workspace on Docker volume),
fall back to `docker cp`:

```rust
// Try bind mount first, fall back to docker cp
match hub.host_path_or_err("/workspaces/corvia-workspace/AGENTS.md") {
    Ok(host_path) => binds.push(format!("{}:/spoke-config/AGENTS.md:ro", host_path)),
    Err(_) => {
        // After container creation, copy files in
        post_create_copies.push(("/workspaces/corvia-workspace/AGENTS.md", "/spoke-config/AGENTS.md"));
    }
}
```

### L6: Graceful Docker Unavailability in Dashboard (QA)

```rust
async fn spokes_handler(State(state): State<Arc<AppState>>) -> Json<SpokesResponse> {
    match &state.docker {
        Some(docker) => {
            match list_spokes(docker).await {
                Ok(spokes) => Json(SpokesResponse { spokes, warning: None }),
                Err(e) => Json(SpokesResponse {
                    spokes: vec![],
                    warning: Some(format!("Docker unavailable: {}", e)),
                }),
            }
        }
        None => Json(SpokesResponse {
            spokes: vec![],
            warning: Some("Docker not connected".into()),
        }),
    }
}
```

Frontend shows banner: "Spoke data unavailable - Docker not connected"

### L7: Destroy --all Confirmation (QA, SWE)

```rust
SpokeCommands::Destroy { name, all, yes } => {
    if all && !yes {
        let spokes = list_running_spokes(&docker).await?;
        if spokes.is_empty() {
            println!("No spokes to destroy.");
            return Ok(());
        }
        println!("This will destroy {} spoke(s):", spokes.len());
        for s in &spokes { println!("  - {}", s.name); }
        print!("Continue? [y/N] ");
        // Read confirmation
        let mut input = String::new();
        std::io::stdin().read_line(&mut input)?;
        if input.trim().to_lowercase() != "y" {
            println!("Cancelled.");
            return Ok(());
        }
    }
    // ... proceed with destroy
}
```

### L8: Agent ID Collision on Reuse (QA)

Append a short timestamp to agent ID:

```rust
let timestamp = chrono::Utc::now().format("%m%d%H%M");
let agent_id = format!("spoke-{}-{}", issue_or_branch, timestamp);
// Example: spoke-42-03281530
```

Corvia knowledge entries from previous attempts remain attributed to the old
agent ID. The dashboard shows the history across attempts.

### L9: Portability Documentation (DevOps)

Add "Supported Environments" section to spoke CLI design:

```
Supported:
  - Linux with Docker Engine (primary)
  - VS Code devcontainers with Docker socket mount
  - GitHub Codespaces (Docker-in-Docker feature)

Limited:
  - macOS Docker Desktop (VM filesystem translation may fail)
  - WSL2 (Docker socket at /var/run/docker.sock, works if exposed)

Not Supported:
  - Podman (different socket API, no compose network)
  - Bare metal without Docker
  - Windows native containers

Use `corvia workspace spoke check` to validate your environment.
```

### L10: Spoke Image Versioning (DevOps)

```dockerfile
ARG CLAUDE_CODE_VERSION=2.1.86
LABEL corvia.spoke.claude_code_version=${CLAUDE_CODE_VERSION}
```

Image tag includes Claude Code version:
```
corvia-spoke:latest
corvia-spoke:cc-2.1.86
```

### L11: Container Name Collision Across Workspaces (DevOps)

Include workspace name in container name:

```rust
let workspace_name = config.project.name.replace(|c: char| !c.is_alphanumeric(), "-");
let spoke_name = format!("corvia-{}-spoke-{}", workspace_name, issue_or_branch);
// Example: corvia-demo-spoke-42
```

### L12: Log Rotation (DevOps, PM)

Already addressed in I2 (resource limits). Applied via HostConfig:
```rust
log_config: Some(LogConfig {
    typ: Some("json-file".into()),
    config: Some(HashMap::from([
        ("max-size".into(), "50m".into()),
        ("max-file".into(), "3".into()),
    ])),
}),
```

### L13: Non-Root Spoke Containers (Security)

Updated Dockerfile:
```dockerfile
FROM node:22-bookworm

RUN apt-get update && apt-get install -y git curl build-essential gh && \
    rm -rf /var/lib/apt/lists/*

ARG CLAUDE_CODE_VERSION=2.1.86
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

# Create non-root user
RUN useradd -m -s /bin/bash spoke
USER spoke
WORKDIR /workspace

COPY --chown=spoke:spoke spoke-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/spoke-entrypoint.sh

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pgrep -f "claude" || exit 1

ENTRYPOINT ["/usr/local/bin/spoke-entrypoint.sh"]
```

Entrypoint adjusts credential permissions:
```bash
# Credentials mounted as root:root, copy to user-owned location
mkdir -p ~/.claude
cp /spoke-config/.credentials.json ~/.claude/.credentials.json 2>/dev/null || true
chmod 600 ~/.claude/.credentials.json
```

### L14: Credential Rotation/Revocation (Security)

Document the mechanism:

```
To revoke a compromised spoke's access:
  1. corvia workspace spoke destroy <name>  (kills the container)
  2. The MCP token for that spoke is no longer valid
     (agent_id + token pair removed from registry)
  3. If the shared GITHUB_TOKEN may be compromised:
     - Revoke the token on GitHub
     - Generate a new fine-grained token
     - Restart remaining spokes with the new token

For proactive rotation:
  - Use apiKeyHelper (Tier 3) for Claude Code credentials
  - Use GitHub App installation tokens (short-lived, auto-rotate)
```

---

## Minor Issues

### M1, M8, M9: Unified via corvia-telemetry (DevOps, Security, SWE)

Three deferred items share the same solution: **corvia-telemetry**, not
separate ad-hoc mechanisms.

| Original Issue | Telemetry Approach |
|---|---|
| M1: Docker stats in dashboard | Spoke container metrics emitted as OTel metrics via `corvia-telemetry`. Dashboard traces view already displays spans/metrics. Add `spoke.cpu_percent`, `spoke.memory_bytes` gauge metrics. Collected by the hub's spoke provisioner on the existing 15s poll interval. |
| M8: Audit log for lifecycle events | Spoke create/destroy emitted as `tracing::info_span!("spoke.lifecycle")` events with structured fields (spoke_name, repo, issue, action). These flow through corvia-telemetry's existing exporters (stdout, file, OTLP). The dashboard Traces tab already renders them. No separate audit system needed. |
| M9: Spoke log capture | Spoke entrypoint streams Claude Code output to the hub via a lightweight log shipper (or `docker logs` API from the hub). Ingested as `tracing::info!` events tagged with `spoke.name`. Searchable in the existing Traces/Logs views. |

**Why telemetry, not corvia_write:** These are operational signals, not knowledge.
They don't belong in the knowledge store (they'd pollute search results and
consume embedding compute). `corvia-telemetry` already has the pipeline:
structured tracing -> exporters -> dashboard. Spoke metrics and lifecycle events
are just new span/metric types flowing through the same pipe.

**Implementation:** Add `spoke.*` span names to `corvia-telemetry/src/lib.rs`
span name constants. The hub's `SpokeProvisioner` emits spans on create/destroy.
The dashboard poll emits gauge metrics for running spoke resource usage.

Deferred to Phase 2, but the approach is defined.

### M2: Spoke Detection by Lookup (SWE)

```typescript
// Use spokeMap instead of string prefix
const isSpoke = spokeMap.has(entry.agent_id);
```

### M3: Poll Interval (PM, DevOps)

Spokes: 15-second interval. Agents: 5-second interval.

```typescript
const spokes = usePoll(fetchSpokes, 15000);
const agents = usePoll(fetchAgents, 5000);
```

### M4: Spoke Restart Command (PM)

Add `corvia workspace spoke restart <name>`:

```rust
SpokeCommands::Restart { name } => {
    // Docker restart preserves container and volumes
    docker.restart_container(&spoke_name, Some(StopContainerOptions { t: 10 })).await?;
    println!("Spoke '{}' restarted.", spoke_name);
}
```

This preserves the repo checkout. The entrypoint re-runs from the beginning
(skips clone since `/workspace` already has files, checks MCP, starts Claude Code).

Entrypoint adjustment:
```bash
# Skip clone if workspace already populated
if [ -d "/workspace/.git" ]; then
    echo "Workspace already populated, skipping clone."
    git fetch origin && git pull --rebase || true
else
    git clone --depth 100 --branch "${DEFAULT_BRANCH}" "${REPO_URL}" /workspace
fi
```

### M5: Issue Link from Repo URL (PM, QA)

Derive from repo config:
```typescript
function issueUrl(repoUrl: string, issue: string): string {
    // Parse "https://github.com/owner/repo.git" -> "https://github.com/owner/repo/issues/N"
    const match = repoUrl.match(/github\.com[:/]([^/]+\/[^/.]+)/);
    if (match) return `https://github.com/${match[1]}/issues/${issue}`;
    return "#"; // fallback: no link
}
```

### M6: MCP Rate Limiting (Security)

Defer to Phase 2. When implemented, add per-agent-id rate limits:
- Writes: 60/minute
- Reads: 300/minute
- Destructive ops (gc_run, rebuild_index): 1/minute

### M7: Secret Content Filter (Security)

Defer to Phase 2. When implemented, add regex scan on `corvia_write` content:
- API key patterns (`sk-`, `ghp_`, `gho_`, `AKIA`)
- Base64-encoded credentials
- Connection strings with passwords

Warn, don't block (false positives are worse than missed secrets for dev use).

### M8, M9: Merged into M1 (corvia-telemetry)

See M1 above. Audit log and spoke log capture are both telemetry concerns,
handled via `corvia-telemetry` spans and metrics, not `corvia_write`.

### M10: Git Clone Retry (QA)

```bash
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
```
