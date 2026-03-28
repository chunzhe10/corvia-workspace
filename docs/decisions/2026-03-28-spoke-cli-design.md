# Spoke CLI Design

**Date:** 2026-03-28
**Status:** Design Complete (review fixes incorporated 2026-03-28)
**Depends on:** Multi-Spoke Workspace Brainstorm (2026-03-28)
**Scope:** corvia-cli, corvia-kernel (DockerProvisioner), corvia-common (config)

---

## Overview

`corvia workspace spoke` is a new subcommand group that manages spoke containers.
Each spoke is a Docker container running Claude Code on one issue/branch, connected
to the hub's corvia server via MCP.

```
corvia workspace spoke create --repo corvia --issue 42
corvia workspace spoke list
corvia workspace spoke logs spoke-42
corvia workspace spoke destroy spoke-42
corvia workspace spoke destroy --all
```

---

## CLI Surface

### `corvia workspace spoke create`

```
corvia workspace spoke create
    --repo <name>           # Which repo to clone (must be in corvia.toml [[repos]])
    --issue <number>        # GitHub issue number (determines branch name + dev-loop target)
    --branch <name>         # Explicit branch name (alternative to --issue)
    --name <name>           # Override spoke name (default: corvia-{workspace}-spoke-{issue}-{timestamp})
    --image <image>         # Override Docker image (default: from config or corvia-spoke:latest)
    --memory <size>         # Memory limit (default: 4g from config)
    --cpus <count>          # CPU limit (default: from config)
    --force                 # Replace existing spoke with same name
    --no-start              # Create container but don't start Claude Code
    --no-github             # Skip GITHUB_TOKEN validation
    --interactive           # Start interactive claude session instead of headless dev-loop
    --allow-runtime-install # Allow npm install claude-code at runtime (dev only)

corvia workspace spoke check        # Validate environment is spoke-capable
corvia workspace spoke restart <name>  # Restart spoke, preserving repo checkout
```

**What it does:**

1. **Pre-flight validation**
   ```rust
   fn preflight_checks(config: &CorviaConfig, hub: &HubContext) -> Result<()> {
       // Docker socket accessible
       Docker::connect_with_local_defaults()
           .map_err(|_| CorviaError::Config("Docker socket not accessible"))?;
       // Credentials exist (via hub path resolution)
       hub.host_path_or_err("/root/.claude/.credentials.json")?;
       // GITHUB_TOKEN
       if std::env::var("GITHUB_TOKEN").unwrap_or_default().is_empty() && !no_github {
           return Err(CorviaError::Config(
               "GITHUB_TOKEN required. Use --no-github to skip.".into()));
       }
       // Disk space (warn if < 4GB free)
       check_disk_space()?;
       Ok(())
   }
   ```

2. **Resolve hub identity (with container detection)**
   ```rust
   let hub = HubContext::detect(&docker).await?;
   // Checks /.dockerenv or /proc/1/cgroup before proceeding.
   // Returns error with clear message if not in a container.
   // Extracts host mount paths via docker inspect.
   ```

3. **Resolve Docker network (deterministic)**
   ```rust
   let network = select_network(&hub.networks, spoke_config.network.as_deref())?;
   // Filters out bridge/host/none, prefers "devcontainer" networks.
   // Errors with list of candidates if ambiguous.
   // Config override via [workspace.spokes] network takes priority.
   ```

4. **Check for duplicate spoke name**
   ```rust
   let timestamp = chrono::Utc::now().format("%m%d%H%M");
   let workspace_slug = config.project.name.replace(|c: char| !c.is_alphanumeric(), "-");
   let spoke_name = format!("corvia-{}-spoke-{}-{}", workspace_slug, issue_or_branch, timestamp);

   // Check for existing container with same base name
   if let Some(existing) = find_spoke(&docker, &base_name).await? {
       if existing.state == "running" && !force {
           return Err("Spoke already running. Use --force to replace.".into());
       }
       if force {
           docker.remove_container(&existing.name, None).await?;
       }
   }
   ```

5. **Generate per-spoke auth token**
   ```rust
   let spoke_token = uuid::Uuid::new_v4().to_string();
   let mcp_token = std::fs::read_to_string(data_dir.join("mcp-token"))?;
   ```

6. **Create the container (with resource limits)**
   ```rust
   let spoke_config = config.spoke_config(); // helper, handles nested Options

   let container = ContainerCreateBody {
       image: Some(spoke_config.image.unwrap_or("corvia-spoke:latest".into())),
       host_config: Some(HostConfig {
           binds: Some(vec![
               format!("{}/.credentials.json:/spoke-config/.credentials.json:ro",
                       hub.host_path_or_err("/root/.claude")?),
               format!("{}:/spoke-config/AGENTS.md:ro",
                       hub.host_path_or_err("/workspaces/corvia-workspace/AGENTS.md")?),
               format!("{}:/spoke-config/CLAUDE.md:ro",
                       hub.host_path_or_err("/workspaces/corvia-workspace/CLAUDE.md")?),
               format!("{}:/spoke-config/skills:ro",
                       hub.host_path_or_err("/workspaces/corvia-workspace/.agents/skills")?),
           ]),
           network_mode: Some(network.clone()),
           memory: Some(parse_memory_limit(&spoke_config.memory_limit)),  // default 4GB
           cpu_shares: Some(spoke_config.cpu_shares as i64),              // default 512
           log_config: Some(LogConfig {
               typ: Some("json-file".into()),
               config: Some(HashMap::from([
                   ("max-size".into(), "50m".into()),
                   ("max-file".into(), "3".into()),
               ])),
           }),
           ..Default::default()
       }),
       env: Some(vec![
           format!("CORVIA_AGENT_ID={}", agent_id),
           format!("CORVIA_SPOKE_TOKEN={}", spoke_token),
           format!("CORVIA_MCP_URL=http://app:8020/mcp"),
           format!("CORVIA_MCP_TOKEN={}", mcp_token),
           format!("CORVIA_REPO_URL={}", repo.url),
           format!("CORVIA_ISSUE={}", issue.unwrap_or(0)),
           format!("CORVIA_BRANCH={}", branch_name),
           format!("GITHUB_TOKEN={}", github_token),
       ]),
       labels: Some(HashMap::from([
           ("corvia.spoke".into(), "true".into()),
           ("corvia.workspace".into(), config.project.name.clone()),
           ("corvia.repo".into(), repo_name.into()),
           ("corvia.issue".into(), issue.map(|i| i.to_string()).unwrap_or_default()),
           ("corvia.branch".into(), branch_name.clone()),
           ("corvia.agent_id".into(), agent_id.clone()),
       ])),
       working_dir: Some("/workspace".into()),
       ..Default::default()
   };
   ```

7. **Start, register, and emit telemetry**
   ```rust
   docker.start_container(&spoke_name).await?;

   // Register spoke agent with auth token in corvia registry
   coordinator.register_spoke_agent(&agent_id, &bcrypt::hash(&spoke_token)?)?;

   // Emit lifecycle telemetry span
   tracing::info_span!("spoke.lifecycle",
       spoke_name = %spoke_name,
       action = "create",
       repo = %repo.name,
       issue = %issue.unwrap_or(0),
   );

   println!("Spoke '{}' started", spoke_name);
   println!("  Repo:   {}", repo.name);
   println!("  Branch: {}", branch_name);
   println!("  Issue:  #{}", issue.unwrap_or(0));
   println!("  Agent:  {}", agent_id);
   println!("  Memory: {}", spoke_config.memory_limit);
   ```

### `corvia workspace spoke list`

```
corvia workspace spoke list
    --all                   # Include stopped/exited spokes
    --json                  # JSON output for scripting
```

**Implementation:**
```rust
// List containers with label filter
let filters = HashMap::from([
    ("label".into(), vec!["corvia.spoke=true".into()]),
]);
let containers = docker.list_containers(Some(options)).await?;

// Merge with corvia agent registry for heartbeat status
let agents = coordinator.registry.list()?;
let agent_map: HashMap<_, _> = agents.iter()
    .map(|a| (a.agent_id.as_str(), a)).collect();

// Output table with failure reason:
// NAME          REPO    BRANCH              ISSUE  STATUS    REASON
// spoke-42      corvia  feat/42-bm25        #42    running   healthy
// spoke-55      corvia  feat/55-graph-viz   #55    running   healthy
// spoke-61      corvia  feat/61-auth        #61    exited    Clone failed (exit 128)
// spoke-70      corvia  feat/70-perf        #70    exited    MCP unreachable
```

For exited containers, extract failure reason from Docker inspect
(exit code) and last 5 lines of container logs.

### `corvia workspace spoke logs`

```
corvia workspace spoke logs <name>
    --follow                # Stream logs (docker logs -f)
    --tail <n>              # Last N lines (default: 50)
```

**Implementation:**
```rust
let log_options = LogsOptionsBuilder::new()
    .follow(follow)
    .tail(tail.to_string())
    .build();
let stream = docker.logs(&spoke_name, Some(log_options));
// Stream to stdout
```

### `corvia workspace spoke destroy`

```
corvia workspace spoke destroy <name>
    --all                   # Destroy all spokes (requires --yes)
    --yes                   # Skip confirmation for --all
    --force                 # Don't wait for graceful shutdown
```

**Implementation:**
```rust
// Graceful: send SIGTERM, wait 10s, then SIGKILL
docker.stop_container(&spoke_name, Some(StopContainerOptions { t: 10 })).await?;
docker.remove_container(&spoke_name, None).await?;
println!("Spoke '{}' destroyed", spoke_name);
```

---

## Spoke Container Entrypoint

The spoke container needs a startup script that:
1. Installs Claude Code (if not in image)
2. Clones the repo
3. Creates the feature branch
4. Writes `.mcp.json`
5. Writes `CLAUDE.md` / `AGENTS.md` (or copies from hub)
6. Starts Claude Code

### Entrypoint Script (embedded in container or generated)

```bash
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

# --- 1. Verify Claude Code is installed (pre-built image) ---
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
if [ -n "${ISSUE}" ]; then
    ISSUE_TITLE=$(gh issue view "${ISSUE}" --json title --jq '.title' 2>/dev/null || echo "")
    SLUG=$(echo "${ISSUE_TITLE}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | head -c 40)
    BRANCH_NAME="feat/${ISSUE}-${SLUG}"
    if git ls-remote --heads origin "${BRANCH_NAME}" | grep -q .; then
        git fetch origin "${BRANCH_NAME}" && git checkout "${BRANCH_NAME}"
    else
        git checkout -b "${BRANCH_NAME}"
    fi
elif [ -n "${BRANCH}" ]; then
    git checkout -b "${BRANCH}" 2>/dev/null || git checkout "${BRANCH}"
fi

# --- 5. Write MCP config (with auth token) ---
cat > /workspace/.mcp.json << EOF
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

# --- 6. Copy workspace instruction files ---
cp /spoke-config/AGENTS.md /workspace/AGENTS.md 2>/dev/null || true
cp /spoke-config/CLAUDE.md /workspace/CLAUDE.md 2>/dev/null || true
mkdir -p /workspace/.agents
cp -r /spoke-config/skills /workspace/.agents/skills 2>/dev/null || true

# --- 7. Write Claude Code settings (scoped permissions) ---
mkdir -p ~/.claude
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
    if curl -sf "${MCP_URL%/mcp}/api/dashboard/status" >/dev/null 2>&1; then
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
if [ -n "${ISSUE}" ]; then
    claude -p "/dev-loop ${ISSUE}" || EXIT_CODE=$?
else
    claude || EXIT_CODE=$?
fi

# --- 10. Report completion ---
report_failure "Spoke exited (code ${EXIT_CODE}). Issue #${ISSUE}."
exit $EXIT_CODE
```

### Environment Variables (passed by `spoke create`)

| Env Var | Source | Purpose |
|---------|--------|---------|
| `CORVIA_REPO_URL` | From `corvia.toml` repo config | Git clone URL |
| `CORVIA_BRANCH` | From `--branch` or `feat/<issue>-<desc>` | Feature branch name |
| `CORVIA_ISSUE` | From `--issue` | GitHub issue number for dev-loop |
| `CORVIA_MCP_URL` | Hub's MCP endpoint | corvia server connection |
| `CORVIA_AGENT_ID` | Generated `spoke-<issue>` | Unique agent identity |
| `GITHUB_TOKEN` | From hub's env | Git push and gh CLI auth |

---

## Spoke Image

### Minimal image (quick start, ~45s startup)

Use `node:22-bookworm` as base. Install Claude Code + git at container start.
Good for prototyping but slow.

### Pre-built image (production, ~5s startup)

```dockerfile
FROM node:22-bookworm

# System tools + GitHub CLI
RUN apt-get update && apt-get install -y git curl build-essential && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

# Claude Code (pinned version, never @latest)
ARG CLAUDE_CODE_VERSION=2.1.86
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}
LABEL corvia.spoke.claude_code_version=${CLAUDE_CODE_VERSION}

# Non-root user
RUN useradd -m -s /bin/bash spoke
USER spoke
WORKDIR /workspace

# Spoke entrypoint
COPY --chown=spoke:spoke spoke-entrypoint.sh /usr/local/bin/spoke-entrypoint.sh
RUN chmod +x /usr/local/bin/spoke-entrypoint.sh

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pgrep -f "claude" || exit 1

ENTRYPOINT ["/usr/local/bin/spoke-entrypoint.sh"]
```

Build: `corvia workspace spoke build-image --claude-version 2.1.86`
Tags: `corvia-spoke:latest`, `corvia-spoke:cc-2.1.86`

---

## Config Extension

### corvia.toml

```toml
[workspace.spokes]
image = "node:22-bookworm"          # Default spoke image
network = ""                         # Auto-detect from hub container
auth_mode = "credentials"            # "credentials" or "api_key"
# api_key = ""                       # Only if auth_mode = "api_key"
```

### SpokeConfig (Rust)

```rust
// In corvia-common/src/config.rs

#[derive(Debug, Deserialize, Serialize, Clone, Default)]
pub struct SpokeConfig {
    pub image: Option<String>,          // default: "corvia-spoke:latest"
    pub network: Option<String>,        // auto-detect if None
    pub auth_mode: Option<SpokeAuthMode>,
    #[serde(default = "default_memory_limit")]
    pub memory_limit: String,           // default: "4g"
    #[serde(default = "default_cpu_shares")]
    pub cpu_shares: u32,                // default: 512
}

fn default_memory_limit() -> String { "4g".into() }
fn default_cpu_shares() -> u32 { 512 }

#[derive(Debug, Deserialize, Serialize, Clone, Default)]
#[serde(rename_all = "snake_case")]
pub enum SpokeAuthMode {
    #[default]
    Credentials,
    ApiKey,
}

// Add to WorkspaceConfig:
pub struct WorkspaceConfig {
    pub repos_dir: String,
    pub repos: Vec<RepoConfig>,
    pub docs: Option<DocsConfig>,
    pub spokes: Option<SpokeConfig>,    // NEW
}

// Helper to avoid double-Option unwrapping:
impl CorviaConfig {
    pub fn spoke_config(&self) -> SpokeConfig {
        self.workspace.as_ref()
            .and_then(|w| w.spokes.clone())
            .unwrap_or_default()
    }
}
```

Recommended spoke counts by machine size:
```
8GB host:  2 spokes (4GB each)
16GB host: 4 spokes (4GB each)
32GB host: 8 spokes (4GB each)
```

---

## State Tracking

Spoke state is tracked via Docker labels (not files). This is stateless. The
`spoke list` command just queries Docker for containers with `corvia.spoke=true`.

If the hub container is destroyed, spoke containers persist in Docker. They can
be listed/destroyed via `docker ps --filter label=corvia.spoke=true`.

Agent registration in corvia's `coordination.redb` provides persistent history.
Even after a spoke is destroyed, its knowledge entries and agent record remain.

---

## Hub Path Resolution

The critical piece for Docker-from-Docker. The hub must translate its container
paths to host paths for bind mounts into spokes.

```rust
/// Resolve host paths by inspecting the hub container's mounts.
pub struct HubContext {
    pub container_name: String,
    pub networks: HashMap<String, NetworkSettings>,
    pub host_mounts: HashMap<String, String>,  // container_path -> host_path
}

impl HubContext {
    pub async fn detect(docker: &Docker) -> Result<Self> {
        // Check if we're inside a container
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

        let hostname = std::env::var("HOSTNAME")
            .or_else(|_| std::fs::read_to_string("/etc/hostname").map(|s| s.trim().to_string()))
            .map_err(|_| CorviaError::Config("Cannot determine container hostname".into()))?;

        let inspect = docker.inspect_container(&hostname, None).await
            .map_err(|e| CorviaError::Docker(format!("Cannot inspect hub container: {e}")))?;

        let mut host_mounts = HashMap::new();
        if let Some(mounts) = inspect.mounts {
            for m in mounts {
                if let (Some(src), Some(dst)) = (m.source, m.destination) {
                    host_mounts.insert(dst, src);
                }
            }
        }

        let networks = inspect.network_settings
            .and_then(|ns| ns.networks)
            .unwrap_or_default();

        Ok(Self { container_name: hostname, networks, host_mounts })
    }

    /// Translate a container path to a host path. Returns Result with diagnostic.
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

    fn host_path(&self, container_path: &str) -> Option<String> {
        let mut best_match: Option<(&str, &str)> = None;
        for (cpath, hpath) in &self.host_mounts {
            if container_path.starts_with(cpath.as_str()) {
                if best_match.map_or(true, |(bp, _)| cpath.len() > bp.len()) {
                    best_match = Some((cpath.as_str(), hpath.as_str()));
                }
            }
        }
        best_match.map(|(cpath, hpath)| {
            let suffix = &container_path[cpath.len()..];
            format!("{}{}", hpath, suffix)
        })
    }
}

/// Select the correct Docker network, deterministically.
fn select_network(
    networks: &HashMap<String, NetworkSettings>,
    config_override: Option<&str>,
) -> Result<String> {
    if let Some(net) = config_override {
        if networks.contains_key(net) { return Ok(net.to_string()); }
        return Err(CorviaError::Config(format!(
            "Configured network '{}' not found. Available: {:?}",
            net, networks.keys().collect::<Vec<_>>()
        )));
    }
    let candidates: Vec<_> = networks.keys()
        .filter(|n| !matches!(n.as_str(), "bridge" | "host" | "none"))
        .collect();
    match candidates.len() {
        0 => Err(CorviaError::Config("No user-defined Docker network found.".into())),
        1 => Ok(candidates[0].clone()),
        _ => {
            if let Some(net) = candidates.iter().find(|n| n.contains("devcontainer")) {
                return Ok(net.to_string());
            }
            Err(CorviaError::Config(format!(
                "Multiple networks: {:?}. Set [workspace.spokes] network in corvia.toml.",
                candidates
            )))
        }
    }
}
```

---

## Sequence Diagram

```
User: corvia workspace spoke create --repo corvia --issue 42

  Hub CLI                    Docker Daemon               Spoke Container
  --------                   -------------               ---------------
  1. load_config()
  2. HubContext::detect()
     |--inspect(hostname)-->|
     |<--mounts, network----|
  3. Resolve host creds path
  4. Find repo URL from config
  5. Generate spoke name
  6. Create container
     |--create_container--->|
     |                      |--pull image (if needed)
     |<--container_id-------|
  7. Start container
     |--start_container---->|
     |                      |--entrypoint.sh----------->|
     |                      |                           | npm install claude
     |                      |                           | git clone
     |                      |                           | write .mcp.json
     |                      |                           | claude -p "/dev-loop 42"
     |                      |                           |   |
     |                      |                           |   |--corvia_search-->Hub MCP
     |                      |                           |   |--corvia_write--->Hub MCP
     |                      |                           |   |--gh pr create--->GitHub
  8. Print spoke info
     |
     Done
```

---

## Implementation Plan

### Files to modify (corvia repo)

| File | Change |
|------|--------|
| `crates/corvia-common/src/config.rs` | Add `SpokeConfig`, `SpokeAuthMode` |
| `crates/corvia-kernel/src/docker.rs` | Add `SpokeProvisioner` (extend `DockerProvisioner`) |
| `crates/corvia-kernel/src/lib.rs` | Export spoke types |
| `crates/corvia-cli/src/main.rs` | Add `SpokeCommands` enum, `cmd_spoke()` dispatcher |
| `crates/corvia-cli/src/spoke.rs` | NEW: spoke command implementations |

### Files to add (workspace repo)

| File | Purpose |
|------|---------|
| `.spoke/spoke-entrypoint.sh` | Entrypoint script for spoke containers |
| `.spoke/Dockerfile` | Pre-built spoke image definition |

### Estimated tasks

1. `SpokeConfig` in corvia-common (config types + helper)
2. `HubContext` + `select_network` in corvia-kernel (Docker path resolution)
3. `SpokeProvisioner` in corvia-kernel (create/list/destroy/restart/check)
4. MCP bearer token auth middleware in corvia-server
5. Per-spoke agent token registration in corvia-kernel
6. `SpokeCommands` in corvia-cli (CLI surface)
7. `cmd_spoke()` in corvia-cli (command dispatch + preflight checks)
8. Spoke entrypoint script (error reporting, health gate, clone retry, branch naming)
9. Pre-built Dockerfile (non-root, pinned version, healthcheck)
10. `spoke.*` telemetry spans in corvia-telemetry
11. Tests (see test plan below)
12. Dashboard: spoke metadata in AgentsView (see dashboard design doc)

---

## Test Plan

### Unit Tests
- `HubContext::host_path_or_err` with various mount configs (nested, overlapping, no match)
- `HubContext::detect` container detection (mock /.dockerenv, /proc/1/cgroup)
- `select_network` with 0, 1, N networks (including devcontainer preference)
- `SpokeConfig` deserialization (defaults, overrides, missing section)
- `CorviaConfig::spoke_config()` helper with nested Options
- Spoke name generation (from issue, from branch, timestamp, workspace prefix)
- `preflight_checks` with missing token, missing credentials, no Docker
- MCP bearer token validation (valid, expired, missing, wrong)

### Integration Tests (require Docker)
- Spoke create/list/destroy lifecycle (happy path)
- Duplicate name handling (with and without --force)
- Network resolution on actual compose network
- Credential mount verification (spoke authenticates successfully)
- Resource limits applied correctly (docker inspect shows memory/cpu)
- Log rotation config applied
- Spoke restart preserves repo checkout
- `spoke check` output in valid and invalid environments

### E2E Tests
- Spoke creates, connects to hub MCP, writes knowledge, visible in dashboard
- Spoke runs dev-loop on a test issue, creates PR
- Hub restart during spoke operation (verify MCP reconnect)
- Spoke exits after completion, prune removes container
- Multiple spokes running concurrently, no knowledge conflicts

### Negative Tests
- Docker daemon down at creation time
- Invalid repo name in corvia.toml
- Missing credentials file
- Expired OAuth token mid-session
- Network unreachable between spoke and hub
- Disk full during clone
- Duplicate spoke name without --force
- Missing GITHUB_TOKEN without --no-github

### Platform Matrix
- Linux with Docker Engine (primary, CI)
- GitHub Codespaces (Docker-in-Docker feature)
- macOS Docker Desktop (document limitations)
- WSL2 (Docker socket exposure)

---

## Supported Environments

```
Supported:
  - Linux with Docker Engine (primary)
  - VS Code devcontainers with Docker socket mount
  - GitHub Codespaces (Docker-in-Docker feature)

Limited:
  - macOS Docker Desktop (VM filesystem translation may fail)
  - WSL2 (works if Docker socket exposed at /var/run/docker.sock)

Not Supported:
  - Podman (different socket API, no compose network)
  - Bare metal without Docker
  - Windows native containers

Use `corvia workspace spoke check` to validate your environment.
```

---

## Resolved Design Questions

1. **Spoke container limits**: No cap. Docker handles resource limits naturally.
   If the host runs out of memory/CPU, Docker will refuse to start new containers.

2. **Spoke health monitoring**: Dual-layer. Corvia agent heartbeat for Claude Code
   liveness AND Docker container health check for container-level health. The
   dashboard shows both: container status (running/exited/unhealthy) from Docker,
   and agent activity (active/stale/idle) from corvia registry.

   ```rust
   // In spoke list, merge both sources:
   struct SpokeStatus {
       container_state: String,    // from Docker inspect
       agent_state: Option<String>, // from corvia agent registry
       last_heartbeat: Option<DateTime<Utc>>,
   }
   ```

   Docker HEALTHCHECK in spoke image:
   ```dockerfile
   HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
       CMD pgrep -f "claude" || exit 1
   ```

3. **Auto-cleanup**: Yes. Spokes auto-destroy after PR is merged. Implementation:
   the spoke entrypoint wraps Claude Code. When `claude -p "/dev-loop <issue>"`
   exits (PR merged or failure), the entrypoint posts a final status to corvia
   and the container exits. A hub-side watcher (or cron-style check) prunes
   exited spoke containers. All knowledge persists in corvia regardless.

   ```bash
   # In spoke-entrypoint.sh, after claude exits:
   EXIT_CODE=$?
   curl -s -X POST "${CORVIA_MCP_URL}" \
       -H "Content-Type: application/json" \
       -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",
            \"params\":{\"name\":\"corvia_write\",\"arguments\":{
              \"scope_id\":\"corvia\",\"agent_id\":\"${CORVIA_AGENT_ID}\",
              \"content_role\":\"finding\",\"source_origin\":\"workspace\",
              \"content\":\"Spoke ${CORVIA_AGENT_ID} exited (code ${EXIT_CODE}). Issue #${CORVIA_ISSUE}.\"
            }}}"
   exit $EXIT_CODE
   ```

   Hub-side cleanup (in `spoke list` or periodic):
   ```rust
   // Prune exited spoke containers older than 1 hour
   pub async fn prune_exited_spokes(&self) -> Result<u32> { ... }
   ```

4. **AGENTS.md / CLAUDE.md propagation**: The corvia repo has its own AGENTS.md
   (119 lines, build/test instructions). But the workspace AGENTS.md (320 lines)
   has corvia MCP instructions, dev-loop skill, auto-save rules, etc. Spokes
   need the workspace-level AGENTS.md to know how to use corvia properly.

   **Solution:** Mount workspace AGENTS.md and CLAUDE.md into spokes read-only.
   The entrypoint copies them into the workspace root after clone.

   ```rust
   // In spoke create, add bind mount for workspace instruction files:
   binds.push(format!(
       "{}:/spoke-config/AGENTS.md:ro",
       hub.host_path("/workspaces/corvia-workspace/AGENTS.md").unwrap()
   ));
   binds.push(format!(
       "{}:/spoke-config/CLAUDE.md:ro",
       hub.host_path("/workspaces/corvia-workspace/CLAUDE.md").unwrap()
   ));
   ```

   ```bash
   # In spoke-entrypoint.sh, after clone:
   cp /spoke-config/AGENTS.md /workspace/AGENTS.md 2>/dev/null || true
   cp /spoke-config/CLAUDE.md /workspace/CLAUDE.md 2>/dev/null || true
   ```

   Also mount `.agents/skills/` directory so dev-loop skill is available:
   ```rust
   binds.push(format!(
       "{}:/spoke-config/skills:ro",
       hub.host_path("/workspaces/corvia-workspace/.agents/skills").unwrap()
   ));
   ```

   ```bash
   # In spoke-entrypoint.sh:
   mkdir -p /workspace/.agents
   cp -r /spoke-config/skills /workspace/.agents/skills 2>/dev/null || true
   ```

5. **Spoke-to-spoke visibility**: Spokes discover each other via corvia knowledge
   search and agent registry (via MCP). No Docker socket access in spokes.
   This is sufficient. If a spoke needs to know what other spokes are doing,
   `corvia_search` returns their decisions and findings.
