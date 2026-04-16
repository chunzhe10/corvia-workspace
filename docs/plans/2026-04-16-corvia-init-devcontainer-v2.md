# corvia init + devcontainer v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace broken v1 devcontainer infrastructure with `corvia init` as the single setup + health check command, and simplify startup scripts to match v2's single-binary stdio MCP architecture.

**Architecture:** `corvia init` (Rust) handles all setup: directory creation, config, gitignore, MCP wiring, model download, indexing. Devcontainer scripts shrink to: install binary + `corvia init --yes` + auth forwarding + plugin install. No HTTP server, no process manager, no port polling.

**Tech Stack:** Rust (clap 4, anyhow, toml, serde_json, fastembed 4), Python 3 stdlib (binary installer), bash (devcontainer lifecycle scripts)

**Design spec:** `docs/decisions/2026-04-16-corvia-init-devcontainer-v2-design.md`

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `crates/corvia-core/src/discover.rs` | Project root discovery (walk up to find `.corvia/`) |
| `crates/corvia-core/src/init.rs` | Init logic: create dirs, config, version, gitignore, MCP, models, ingest |
| `crates/corvia-cli/tests/init_e2e.rs` | Integration tests for `corvia init` |
| `.devcontainer/scripts/install_corvia.py` | Standalone binary installer (replaces corvia_dev Python package) |

### Modified files

| File | Changes |
|------|---------|
| `crates/corvia-core/src/lib.rs` | Add `pub mod discover;` and `pub mod init;` |
| `crates/corvia-core/src/config.rs` | `Config::load` uses discover module; add `Config::load_from_dir` |
| `crates/corvia-cli/src/main.rs` | Add `Init` command, update all commands to use project root discovery |
| `crates/corvia-cli/src/mcp.rs` | Use discover module for base_dir; add `--test` flag |
| `.devcontainer/scripts/lib.sh` | Remove corvia-dev, ORT, install_binaries, ensure_tooling |
| `.devcontainer/scripts/post-start.sh` | Rewrite: auth + `corvia init --yes` + plugin |
| `.devcontainer/scripts/post-create.sh` | Rewrite: network + binary install + `corvia init --yes` + extensions |
| `.devcontainer/scripts/init-host.sh` | Remove port allocation, port manifest, ollama, compose profiles |
| `.devcontainer/scripts/setup_telemetry.py` | Replace `_mcp_write` HTTP call with `corvia write` subprocess |
| `.devcontainer/Taskfile.yml` | Remove service management tasks, simplify to match new scripts |
| `.devcontainer/devcontainer.json` | Remove `forwardPorts`, update comments |
| `.mcp.json` | Change from HTTP to stdio |
| `.gitignore` | Replace v1 `.corvia/` entries with single line |

---

## Phase 1: Core Rust Changes

### Task 1: Project root discovery module

**Files:**
- Create: `crates/corvia-core/src/discover.rs`
- Modify: `crates/corvia-core/src/lib.rs`

- [ ] **Step 1: Create discover module with tests**

Create `crates/corvia-core/src/discover.rs`:

```rust
//! Project root discovery — walk up to find `.corvia/corvia.toml`.

use std::path::{Path, PathBuf};

use anyhow::{bail, Result};

/// Walk up from `start` to find a directory containing `.corvia/corvia.toml`.
/// Returns the project root (parent of `.corvia/`).
pub fn find_project_root(start: &Path) -> Result<PathBuf> {
    let mut current = start
        .canonicalize()
        .unwrap_or_else(|_| start.to_path_buf());

    loop {
        let candidate = current.join(".corvia").join("corvia.toml");
        if candidate.is_file() {
            return Ok(current);
        }
        if !current.pop() {
            bail!(
                "No .corvia/ found (searched from {}). Run 'corvia init' to set up.",
                start.display()
            );
        }
    }
}

/// Resolve the project root: use `--base-dir` if provided, otherwise discover.
pub fn resolve_base_dir(explicit: Option<&Path>) -> Result<PathBuf> {
    match explicit {
        Some(dir) => {
            let config = dir.join(".corvia").join("corvia.toml");
            if !config.is_file() {
                bail!(
                    "No .corvia/corvia.toml in {}. Run 'corvia init' first.",
                    dir.display()
                );
            }
            Ok(dir.to_path_buf())
        }
        None => find_project_root(&std::env::current_dir()?),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn finds_root_in_current_dir() {
        let dir = TempDir::new().unwrap();
        let corvia = dir.path().join(".corvia");
        std::fs::create_dir_all(&corvia).unwrap();
        std::fs::write(corvia.join("corvia.toml"), "").unwrap();

        let root = find_project_root(dir.path()).unwrap();
        assert_eq!(root, dir.path().canonicalize().unwrap());
    }

    #[test]
    fn finds_root_from_subdirectory() {
        let dir = TempDir::new().unwrap();
        let corvia = dir.path().join(".corvia");
        std::fs::create_dir_all(&corvia).unwrap();
        std::fs::write(corvia.join("corvia.toml"), "").unwrap();

        let sub = dir.path().join("src").join("deep");
        std::fs::create_dir_all(&sub).unwrap();

        let root = find_project_root(&sub).unwrap();
        assert_eq!(root, dir.path().canonicalize().unwrap());
    }

    #[test]
    fn errors_when_no_corvia_dir() {
        let dir = TempDir::new().unwrap();
        let result = find_project_root(dir.path());
        assert!(result.is_err());
        let msg = result.unwrap_err().to_string();
        assert!(msg.contains("No .corvia/ found"));
    }

    #[test]
    fn resolve_explicit_base_dir() {
        let dir = TempDir::new().unwrap();
        let corvia = dir.path().join(".corvia");
        std::fs::create_dir_all(&corvia).unwrap();
        std::fs::write(corvia.join("corvia.toml"), "").unwrap();

        let root = resolve_base_dir(Some(dir.path())).unwrap();
        assert_eq!(root, dir.path().to_path_buf());
    }

    #[test]
    fn resolve_explicit_missing_errors() {
        let dir = TempDir::new().unwrap();
        let result = resolve_base_dir(Some(dir.path()));
        assert!(result.is_err());
    }
}
```

- [ ] **Step 2: Register module**

Add to `crates/corvia-core/src/lib.rs`:

```rust
pub mod discover;
```

- [ ] **Step 3: Run tests**

Run: `cd /workspaces/corvia-workspace/repos/corvia && cargo test -p corvia-core discover`
Expected: 5 tests pass.

- [ ] **Step 4: Commit**

```bash
git add crates/corvia-core/src/discover.rs crates/corvia-core/src/lib.rs
git commit -m "feat: add project root discovery module (walk up to find .corvia/)"
```

---

### Task 2: Update Config to load from `.corvia/corvia.toml`

**Files:**
- Modify: `crates/corvia-core/src/config.rs`

The current `Config::load` takes an explicit path. We add `Config::load_discovered`
which uses the discover module to find the config from a base directory.

- [ ] **Step 1: Add `Config::load_discovered` method**

In `crates/corvia-core/src/config.rs`, add after the existing `load` method (after line ~194):

```rust
    /// Load config from a discovered project root.
    /// Looks for `.corvia/corvia.toml` relative to `base_dir`.
    pub fn load_discovered(base_dir: &Path) -> Result<Self> {
        let config_path = base_dir.join(".corvia").join("corvia.toml");
        Self::load(&config_path)
    }
```

- [ ] **Step 2: Add test for load_discovered**

Add to the existing `#[cfg(test)] mod tests` block in `config.rs`:

```rust
    #[test]
    fn load_discovered_from_corvia_dir() {
        let dir = tempfile::TempDir::new().unwrap();
        let corvia = dir.path().join(".corvia");
        std::fs::create_dir_all(&corvia).unwrap();
        std::fs::write(
            corvia.join("corvia.toml"),
            "[embedding]\nmodel = \"test-model\"\nreranker_model = \"test-reranker\"\n",
        )
        .unwrap();

        let config = Config::load_discovered(dir.path()).unwrap();
        assert_eq!(config.embedding.model, "test-model");
    }

    #[test]
    fn load_discovered_missing_returns_defaults() {
        let dir = tempfile::TempDir::new().unwrap();
        let corvia = dir.path().join(".corvia");
        std::fs::create_dir_all(&corvia).unwrap();
        // No corvia.toml — load should return defaults (NotFound -> Default)
        let config = Config::load_discovered(dir.path()).unwrap();
        assert_eq!(config.embedding.model, "nomic-embed-text-v1.5");
    }
```

- [ ] **Step 3: Run tests**

Run: `cd /workspaces/corvia-workspace/repos/corvia && cargo test -p corvia-core config`
Expected: existing tests + 2 new tests pass.

- [ ] **Step 4: Commit**

```bash
git add crates/corvia-core/src/config.rs
git commit -m "feat: add Config::load_discovered for .corvia/corvia.toml loading"
```

---

### Task 3: Update CLI commands to use project root discovery

**Files:**
- Modify: `crates/corvia-cli/src/main.rs`
- Modify: `crates/corvia-cli/src/mcp.rs`

All commands currently hardcode `Path::new("corvia.toml")` and `Path::new(".")`.
Update them to use `discover::resolve_base_dir`.

- [ ] **Step 1: Add `--base-dir` global arg to Cli struct**

In `crates/corvia-cli/src/main.rs`, update the `Cli` struct:

```rust
#[derive(Parser)]
#[command(name = "corvia", version, about = "Organizational memory for AI agents")]
struct Cli {
    /// OTLP gRPC endpoint for exporting traces (e.g. http://localhost:4317).
    /// Can also be set via OTEL_EXPORTER_OTLP_ENDPOINT env var.
    #[arg(long, global = true)]
    otlp_endpoint: Option<String>,

    /// Project root directory (default: auto-discover by walking up to find .corvia/)
    #[arg(long, global = true)]
    base_dir: Option<std::path::PathBuf>,

    #[command(subcommand)]
    command: Command,
}
```

- [ ] **Step 2: Create helper function for resolved config loading**

Add after the `Cli` and `Command` definitions in `main.rs`:

```rust
/// Resolve the project root and load config.
/// Used by all commands except `Init` (which creates .corvia/).
fn load_config(base_dir_arg: Option<&Path>) -> anyhow::Result<(PathBuf, Config)> {
    let base_dir = corvia_core::discover::resolve_base_dir(base_dir_arg)?;
    let config = Config::load_discovered(&base_dir)?;
    Ok((base_dir, config))
}
```

- [ ] **Step 3: Update all command handlers to accept base_dir**

Update the dispatch in `main()` to pass `cli.base_dir`:

```rust
    let result = match cli.command {
        Command::Ingest {
            path,
            fresh,
            model_path,
        } => cmd_ingest(cli.base_dir.as_deref(), path.as_deref(), fresh, model_path),
        Command::Search {
            query,
            limit,
            kind,
            max_tokens,
        } => cmd_search(cli.base_dir.as_deref(), &query, limit, kind.as_deref(), max_tokens),
        Command::Write {
            content,
            kind,
            tags,
            supersedes,
        } => cmd_write(cli.base_dir.as_deref(), &content, &kind, tags.as_deref(), supersedes.as_deref()),
        Command::Status => cmd_status(cli.base_dir.as_deref()),
        Command::Traces { limit, filter } => cmd_traces(cli.base_dir.as_deref(), limit, filter.as_deref()),
        Command::Mcp => mcp::run(cli.base_dir.as_deref()).await,
    };
```

Update each command handler signature and body to use `load_config`. For example,
`cmd_ingest` becomes:

```rust
fn cmd_ingest(
    base_dir_arg: Option<&Path>,
    path: Option<&Path>,
    fresh: bool,
    model_path: Option<std::path::PathBuf>,
) -> anyhow::Result<()> {
    let (base_dir, mut config) = load_config(base_dir_arg)?;

    if let Some(mp) = model_path {
        config.embedding.model_path = Some(mp);
    }

    let ingest_path = path.unwrap_or(&base_dir);
    let result = corvia_core::ingest::ingest(&config, ingest_path, fresh)?;

    println!(
        "Ingested {} entries ({} chunks). Superseded: {}. Skipped: {}.",
        result.entries_ingested,
        result.chunks_indexed,
        result.superseded_count,
        result.entries_skipped.len(),
    );

    if !result.entries_skipped.is_empty() {
        for (file, reason) in &result.entries_skipped {
            println!("  skipped: {file} ({reason})");
        }
    }

    Ok(())
}
```

Apply the same pattern to `cmd_search`, `cmd_write`, `cmd_status`, `cmd_traces`:
replace `Config::load(Path::new("corvia.toml"))` with `load_config(base_dir_arg)`,
and replace `Path::new(".")` with `&base_dir`.

- [ ] **Step 4: Update mcp.rs to accept base_dir**

In `crates/corvia-cli/src/mcp.rs`, update the `run` function signature (line ~466):

```rust
pub async fn run(base_dir_arg: Option<&Path>) -> Result<()> {
    let base_dir = corvia_core::discover::resolve_base_dir(base_dir_arg)?;
    let config = Config::load_discovered(&base_dir)
        .context("loading config")?;
```

Add `use std::path::Path;` to the imports if not present.

- [ ] **Step 5: Verify compilation**

Run: `cd /workspaces/corvia-workspace/repos/corvia && cargo build -p corvia-cli`
Expected: compiles without errors.

- [ ] **Step 6: Commit**

```bash
git add crates/corvia-cli/src/main.rs crates/corvia-cli/src/mcp.rs
git commit -m "feat: use project root discovery in all CLI commands"
```

---

### Task 4: `corvia init` — directory setup, config, version, locking

**Files:**
- Create: `crates/corvia-core/src/init.rs`
- Modify: `crates/corvia-core/src/lib.rs`
- Modify: `crates/corvia-cli/src/main.rs`

- [ ] **Step 1: Create init module with core logic**

Create `crates/corvia-core/src/init.rs`:

```rust
//! `corvia init` — setup + health check for .corvia/ directory.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use anyhow::{bail, Context, Result};

use crate::config::Config;

/// Schema version written to `.corvia/version`.
/// Bump this when the store layout changes (not on every binary release).
pub const STORE_SCHEMA_VERSION: &str = "1.0.0";

/// Result of running `corvia init`.
#[derive(Debug)]
pub struct InitResult {
    pub base_dir: PathBuf,
    pub created: bool,
    pub config_migrated: bool,
    pub version_updated: bool,
    pub actions: Vec<String>,
}

/// Options for `corvia init`.
pub struct InitOptions {
    /// Auto-accept all prompts (non-interactive).
    pub yes: bool,
    /// Override base directory (default: current directory).
    pub base_dir: Option<PathBuf>,
    /// Force past version checks.
    pub force: bool,
    /// Path to pre-downloaded models.
    pub model_path: Option<PathBuf>,
}

/// Run `corvia init`. Safe to call repeatedly (idempotent).
///
/// Acquires `.corvia/.lock` before making modifications.
pub fn run_init(opts: &InitOptions) -> Result<InitResult> {
    let base_dir = opts
        .base_dir
        .clone()
        .unwrap_or_else(|| std::env::current_dir().expect("cannot determine cwd"));
    let corvia_dir = base_dir.join(".corvia");
    let created = !corvia_dir.exists();

    let mut result = InitResult {
        base_dir: base_dir.clone(),
        created,
        config_migrated: false,
        version_updated: false,
        actions: Vec::new(),
    };

    // Create .corvia/ if missing.
    if created {
        fs::create_dir_all(&corvia_dir)
            .context("failed to create .corvia/ directory")?;
        result.actions.push("created .corvia/".into());
    }

    // Acquire lock before modifications.
    let lock_path = corvia_dir.join(".lock");
    let lock_file = fs::File::create(&lock_path)
        .context("failed to create .corvia/.lock")?;
    fs2::lock_exclusive(&lock_file)
        .context("failed to acquire .corvia/.lock (another corvia init running?)")?;

    // Config: migrate v1 or create defaults.
    ensure_config(&base_dir, &corvia_dir, &mut result)?;

    // Load the config we just ensured exists.
    let config = Config::load(&corvia_dir.join("corvia.toml"))
        .context("failed to load .corvia/corvia.toml after ensure_config")?;

    // Version file.
    ensure_version(&corvia_dir, opts, &mut result)?;

    // Internal .gitignore for derived data.
    ensure_internal_gitignore(&corvia_dir, &mut result)?;

    // Project .gitignore — not managed by init (user's choice).

    // MCP integration (.mcp.json).
    ensure_mcp_json(&base_dir, &mut result)?;

    // Claude Code settings.
    ensure_claude_settings(&base_dir, &mut result)?;

    // Pre-download embedding models so `corvia mcp` starts fast.
    ensure_models(&corvia_dir, &config, opts, &mut result)?;

    Ok(result)
    // lock_file dropped here -> lock released.
}

fn ensure_config(base_dir: &Path, corvia_dir: &Path, result: &mut InitResult) -> Result<()> {
    let v2_config = corvia_dir.join("corvia.toml");

    if v2_config.is_file() {
        // Validate existing config.
        Config::load(&v2_config).context("existing .corvia/corvia.toml is invalid")?;
        return Ok(());
    }

    // Check for v1 config at project root.
    let v1_config = base_dir.join("corvia.toml");
    if v1_config.is_file() {
        fs::copy(&v1_config, &v2_config)
            .context("failed to copy v1 corvia.toml to .corvia/")?;
        let backup = base_dir.join("corvia.toml.v1-backup");
        fs::rename(&v1_config, &backup)
            .context("failed to rename v1 corvia.toml to .v1-backup")?;
        result.config_migrated = true;
        result.actions.push("migrated config from ./corvia.toml".into());
        return Ok(());
    }

    // Write defaults.
    let defaults = Config::default();
    let toml_str = toml::to_string_pretty(&defaults)
        .context("failed to serialize default config")?;
    fs::write(&v2_config, toml_str)
        .context("failed to write default .corvia/corvia.toml")?;
    result.actions.push("created .corvia/corvia.toml (defaults)".into());
    Ok(())
}

fn ensure_version(corvia_dir: &Path, opts: &InitOptions, result: &mut InitResult) -> Result<()> {
    let version_path = corvia_dir.join("version");

    if let Ok(existing) = fs::read_to_string(&version_path) {
        let existing = existing.trim();
        if existing == STORE_SCHEMA_VERSION {
            return Ok(());
        }
        // Simple semver comparison for major.minor.patch.
        if !opts.force && existing > STORE_SCHEMA_VERSION {
            if opts.yes {
                // --yes mode: warn but don't block.
                eprintln!(
                    "warning: store schema v{} is newer than this binary's v{}. \
                     Some features may not work. Upgrade corvia or use --force.",
                    existing, STORE_SCHEMA_VERSION
                );
                return Ok(());
            } else {
                bail!(
                    "store schema v{} is newer than this binary's v{}. \
                     Upgrade corvia or use --force.",
                    existing, STORE_SCHEMA_VERSION
                );
            }
        }
    }

    fs::write(&version_path, STORE_SCHEMA_VERSION)
        .context("failed to write .corvia/version")?;
    result.version_updated = true;
    result.actions.push(format!("set store schema v{STORE_SCHEMA_VERSION}"));
    Ok(())
}

fn ensure_internal_gitignore(corvia_dir: &Path, result: &mut InitResult) -> Result<()> {
    let gitignore_path = corvia_dir.join(".gitignore");
    let expected = "\
# Derived data (rebuilt by corvia init / corvia ingest)
index/
models/
traces.jsonl
version
*.lock

# Source-of-truth files are NOT ignored:
# - corvia.toml (config)
# - entries/ (knowledge entries)
";

    if gitignore_path.is_file() {
        let existing = fs::read_to_string(&gitignore_path).unwrap_or_default();
        if existing.contains("index/") && existing.contains("models/") {
            return Ok(());
        }
    }

    fs::write(&gitignore_path, expected)
        .context("failed to write .corvia/.gitignore")?;
    result.actions.push("created .corvia/.gitignore".into());
    Ok(())
}

fn ensure_mcp_json(base_dir: &Path, result: &mut InitResult) -> Result<()> {
    let mcp_path = base_dir.join(".mcp.json");

    let expected_entry = serde_json::json!({
        "type": "stdio",
        "command": "corvia",
        "args": ["mcp"]
    });

    if mcp_path.is_file() {
        let content = fs::read_to_string(&mcp_path)
            .context("failed to read .mcp.json")?;
        let mut doc: serde_json::Value = match serde_json::from_str(&content) {
            Ok(v) => v,
            Err(e) => {
                eprintln!("warning: .mcp.json has syntax errors ({e}), not modifying");
                return Ok(());
            }
        };

        // Check if corvia entry already matches.
        if let Some(servers) = doc.get("mcpServers") {
            if let Some(entry) = servers.get("corvia") {
                if entry == &expected_entry {
                    return Ok(());
                }
            }
        }

        // Merge: only update the corvia key.
        let servers = doc
            .as_object_mut()
            .unwrap()
            .entry("mcpServers")
            .or_insert_with(|| serde_json::json!({}));
        servers
            .as_object_mut()
            .unwrap()
            .insert("corvia".into(), expected_entry);

        let output = serde_json::to_string_pretty(&doc)?;
        fs::write(&mcp_path, format!("{output}\n"))
            .context("failed to update .mcp.json")?;
        result.actions.push(".mcp.json updated (stdio)".into());
    } else {
        let doc = serde_json::json!({
            "mcpServers": {
                "corvia": expected_entry
            }
        });
        let output = serde_json::to_string_pretty(&doc)?;
        fs::write(&mcp_path, format!("{output}\n"))
            .context("failed to create .mcp.json")?;
        result.actions.push(".mcp.json created (stdio)".into());
    }

    Ok(())
}

fn ensure_claude_settings(base_dir: &Path, result: &mut InitResult) -> Result<()> {
    let claude_dir = base_dir.join(".claude");
    if !claude_dir.is_dir() {
        // No .claude/ directory — skip (not a Claude Code environment).
        return Ok(());
    }

    let settings_path = claude_dir.join("settings.local.json");
    let mut doc: serde_json::Value = if settings_path.is_file() {
        let content = fs::read_to_string(&settings_path)
            .context("failed to read settings.local.json")?;
        serde_json::from_str(&content).unwrap_or_else(|_| serde_json::json!({}))
    } else {
        serde_json::json!({})
    };

    // Append "corvia" to enabledMcpjsonServers if not present.
    let servers = doc
        .as_object_mut()
        .unwrap()
        .entry("enabledMcpjsonServers")
        .or_insert_with(|| serde_json::json!([]));
    if let Some(arr) = servers.as_array_mut() {
        let corvia_val = serde_json::Value::String("corvia".into());
        if !arr.contains(&corvia_val) {
            arr.push(corvia_val);
            let output = serde_json::to_string_pretty(&doc)?;
            fs::write(&settings_path, format!("{output}\n"))
                .context("failed to write settings.local.json")?;
            result.actions.push("settings.local.json updated".into());
        }
    }

    Ok(())
}

fn ensure_models(
    corvia_dir: &Path,
    config: &Config,
    opts: &InitOptions,
    result: &mut InitResult,
) -> Result<()> {
    use crate::embed::Embedder;

    let model_dir = opts
        .model_path
        .clone()
        .unwrap_or_else(|| corvia_dir.join("models"));
    fs::create_dir_all(&model_dir)
        .context("failed to create models directory")?;

    // Try loading the embedder — this downloads models if missing.
    println!("  models:     checking {}...", config.embedding.model);
    match Embedder::new(
        Some(&model_dir),
        &config.embedding.model,
        &config.embedding.reranker_model,
    ) {
        Ok(_) => {
            result.actions.push(format!("models ready ({})", config.embedding.model));
        }
        Err(e) => {
            eprintln!("warning: failed to load embedding model: {e:#}");
            result.actions.push("models: download failed (will retry)".into());
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn opts(dir: &Path) -> InitOptions {
        InitOptions {
            yes: true,
            base_dir: Some(dir.to_path_buf()),
            force: false,
            model_path: None,
        }
    }

    #[test]
    fn fresh_init_creates_directory_and_config() {
        let dir = TempDir::new().unwrap();
        let result = run_init(&opts(dir.path())).unwrap();

        assert!(result.created);
        assert!(dir.path().join(".corvia/corvia.toml").is_file());
        assert!(dir.path().join(".corvia/version").is_file());
        assert!(dir.path().join(".corvia/.gitignore").is_file());

        let version = fs::read_to_string(dir.path().join(".corvia/version")).unwrap();
        assert_eq!(version.trim(), STORE_SCHEMA_VERSION);
    }

    #[test]
    fn idempotent_second_run() {
        let dir = TempDir::new().unwrap();
        run_init(&opts(dir.path())).unwrap();
        let result = run_init(&opts(dir.path())).unwrap();

        // Second run should not recreate.
        assert!(!result.created);
        assert!(!result.config_migrated);
        assert!(!result.version_updated);
    }

    #[test]
    fn migrates_v1_config() {
        let dir = TempDir::new().unwrap();
        fs::write(
            dir.path().join("corvia.toml"),
            "[embedding]\nmodel = \"custom-model\"\nreranker_model = \"custom-reranker\"\n",
        )
        .unwrap();

        let result = run_init(&opts(dir.path())).unwrap();

        assert!(result.config_migrated);
        assert!(dir.path().join(".corvia/corvia.toml").is_file());
        assert!(dir.path().join("corvia.toml.v1-backup").is_file());
        assert!(!dir.path().join("corvia.toml").exists());

        let config = Config::load(&dir.path().join(".corvia/corvia.toml")).unwrap();
        assert_eq!(config.embedding.model, "custom-model");
    }

    #[test]
    fn creates_mcp_json() {
        let dir = TempDir::new().unwrap();
        run_init(&opts(dir.path())).unwrap();

        let content = fs::read_to_string(dir.path().join(".mcp.json")).unwrap();
        let doc: serde_json::Value = serde_json::from_str(&content).unwrap();
        let entry = &doc["mcpServers"]["corvia"];
        assert_eq!(entry["type"], "stdio");
        assert_eq!(entry["command"], "corvia");
    }

    #[test]
    fn preserves_other_mcp_servers() {
        let dir = TempDir::new().unwrap();
        let existing = serde_json::json!({
            "mcpServers": {
                "other-server": {"type": "http", "url": "http://localhost:9999"}
            }
        });
        fs::write(
            dir.path().join(".mcp.json"),
            serde_json::to_string_pretty(&existing).unwrap(),
        )
        .unwrap();

        run_init(&opts(dir.path())).unwrap();

        let content = fs::read_to_string(dir.path().join(".mcp.json")).unwrap();
        let doc: serde_json::Value = serde_json::from_str(&content).unwrap();
        assert!(doc["mcpServers"]["other-server"].is_object());
        assert!(doc["mcpServers"]["corvia"].is_object());
    }

    #[test]
    fn skips_mcp_update_when_already_correct() {
        let dir = TempDir::new().unwrap();
        run_init(&opts(dir.path())).unwrap();

        let mtime_before = fs::metadata(dir.path().join(".mcp.json"))
            .unwrap()
            .modified()
            .unwrap();

        // Small sleep to ensure mtime would differ.
        std::thread::sleep(std::time::Duration::from_millis(50));

        let result = run_init(&opts(dir.path())).unwrap();

        // .mcp.json should not appear in actions (no-op).
        assert!(!result.actions.iter().any(|a| a.contains(".mcp.json")));
    }

    #[test]
    fn claude_settings_appends_not_overwrites() {
        let dir = TempDir::new().unwrap();
        let claude_dir = dir.path().join(".claude");
        fs::create_dir_all(&claude_dir).unwrap();
        fs::write(
            claude_dir.join("settings.local.json"),
            r#"{"enabledMcpjsonServers": ["other-server"]}"#,
        )
        .unwrap();

        run_init(&opts(dir.path())).unwrap();

        let content = fs::read_to_string(claude_dir.join("settings.local.json")).unwrap();
        let doc: serde_json::Value = serde_json::from_str(&content).unwrap();
        let servers = doc["enabledMcpjsonServers"].as_array().unwrap();
        assert!(servers.contains(&serde_json::json!("other-server")));
        assert!(servers.contains(&serde_json::json!("corvia")));
    }

    #[test]
    fn skips_claude_settings_without_claude_dir() {
        let dir = TempDir::new().unwrap();
        run_init(&opts(dir.path())).unwrap();

        // No .claude/ dir should exist.
        assert!(!dir.path().join(".claude").exists());
    }

    #[test]
    fn version_downgrade_warns_in_yes_mode() {
        let dir = TempDir::new().unwrap();
        let corvia = dir.path().join(".corvia");
        fs::create_dir_all(&corvia).unwrap();
        fs::write(corvia.join("corvia.toml"), "").unwrap();
        // Write a "future" version.
        fs::write(corvia.join("version"), "99.0.0").unwrap();

        // --yes mode should warn, not error.
        let result = run_init(&opts(dir.path()));
        assert!(result.is_ok());
    }
}
```

- [ ] **Step 2: Add `fs2` dependency for file locking**

In `crates/corvia-core/Cargo.toml`, add under `[dependencies]`:

```toml
fs2 = "0.4"
```

- [ ] **Step 3: Register init module**

Add to `crates/corvia-core/src/lib.rs`:

```rust
pub mod init;
```

- [ ] **Step 4: Run tests**

Run: `cd /workspaces/corvia-workspace/repos/corvia && cargo test -p corvia-core init`
Expected: all init tests pass.

- [ ] **Step 5: Add Init command to CLI**

In `crates/corvia-cli/src/main.rs`, add to the `Command` enum:

```rust
    /// Initialize corvia in the current directory
    Init {
        /// Auto-accept all prompts
        #[arg(long)]
        yes: bool,
        /// Force past version checks
        #[arg(long)]
        force: bool,
        /// Path to pre-downloaded embedding models
        #[arg(long)]
        model_path: Option<std::path::PathBuf>,
        /// Output format
        #[arg(long, value_parser = ["text", "json"])]
        format: Option<String>,
    },
```

Add the dispatch in `main()`:

```rust
        Command::Init { yes, force, model_path, format } => {
            cmd_init(cli.base_dir, yes, force, model_path, format)
        }
```

Add the handler:

```rust
fn cmd_init(
    base_dir: Option<std::path::PathBuf>,
    yes: bool,
    force: bool,
    model_path: Option<std::path::PathBuf>,
    format: Option<String>,
) -> anyhow::Result<()> {
    use corvia_core::init::{self, InitOptions};

    let is_tty = std::io::IsTerminal::is_terminal(&std::io::stdout());
    let opts = InitOptions {
        yes: yes || !is_tty,
        base_dir,
        force,
        model_path: model_path.clone(),
    };

    let result = init::run_init(&opts)?;

    if format.as_deref() == Some("json") {
        let json = serde_json::json!({
            "status": "ok",
            "created": result.created,
            "config_migrated": result.config_migrated,
            "version_updated": result.version_updated,
            "actions": result.actions,
        });
        println!("{}", serde_json::to_string_pretty(&json)?);
    } else {
        if result.created {
            println!("corvia initialized (.corvia/)");
        } else {
            println!("corvia health check");
        }
        for action in &result.actions {
            println!("  {action}");
        }
        if result.actions.is_empty() {
            println!("  all checks passed");
        }
        println!();
        println!("Try: corvia search \"how does X work?\"");
    }

    Ok(())
}
```

- [ ] **Step 6: Verify compilation**

Run: `cd /workspaces/corvia-workspace/repos/corvia && cargo build -p corvia-cli`
Expected: compiles.

- [ ] **Step 7: Commit**

```bash
git add crates/corvia-core/src/init.rs crates/corvia-core/src/lib.rs \
  crates/corvia-core/Cargo.toml crates/corvia-cli/src/main.rs
git commit -m "feat: add corvia init command with health checklist"
```

---

### Task 5: `corvia mcp --test`

**Files:**
- Modify: `crates/corvia-cli/src/main.rs`
- Modify: `crates/corvia-cli/src/mcp.rs`

- [ ] **Step 1: Add `--test` flag to Mcp command**

In `crates/corvia-cli/src/main.rs`, update the `Mcp` variant:

```rust
    /// Start stdio MCP server
    Mcp {
        /// Run self-test and exit (validates config, models, tools)
        #[arg(long)]
        test: bool,
    },
```

Update the dispatch:

```rust
        Command::Mcp { test } => {
            if test {
                mcp::run_test(cli.base_dir.as_deref()).await
            } else {
                mcp::run(cli.base_dir.as_deref()).await
            }
        }
```

- [ ] **Step 2: Add `run_test` function to mcp.rs**

Add to the end of `crates/corvia-cli/src/mcp.rs`:

```rust
/// Run a self-test: load config, initialize embedder, verify tools, run a
/// test search. Prints a diagnostic report and exits.
pub async fn run_test(base_dir_arg: Option<&Path>) -> Result<()> {
    use std::time::Instant;

    let base_dir = crate::corvia_core::discover::resolve_base_dir(base_dir_arg)?;

    // Config.
    print!("  config:     ");
    let config = Config::load_discovered(&base_dir)
        .context("loading config")?;
    println!(".corvia/corvia.toml (ok)");

    // Models.
    print!("  models:     ");
    let start = Instant::now();
    let cache_dir = config.embedding.model_path.clone();
    let embedder = Embedder::new(
        cache_dir.as_deref(),
        &config.embedding.model,
        &config.embedding.reranker_model,
    )
    .context("initializing embedder")?;
    let elapsed = start.elapsed();
    println!(
        "{} + {} (loaded in {:.1}s)",
        config.embedding.model,
        config.embedding.reranker_model,
        elapsed.as_secs_f64()
    );

    // Tools.
    let server = CorviaServer::new(config, embedder, base_dir);
    let tools = vec![search_tool(), write_tool(), status_tool(), traces_tool()];
    let tool_names: Vec<&str> = tools.iter().map(|t| t.name.as_ref()).collect();
    println!("  tools:      {} ({})", tools.len(), tool_names.join(", "));

    // Status.
    let status = handle_status(&server.config, &server.base_dir)?;
    if let Some(entries) = status.get("entry_count").and_then(|v| v.as_u64()) {
        println!("  entries:    {entries}");
    }

    println!("  status:     ready");
    Ok(())
}
```

- [ ] **Step 3: Verify compilation**

Run: `cd /workspaces/corvia-workspace/repos/corvia && cargo build -p corvia-cli`
Expected: compiles.

- [ ] **Step 4: Commit**

```bash
git add crates/corvia-cli/src/main.rs crates/corvia-cli/src/mcp.rs
git commit -m "feat: add corvia mcp --test for MCP self-diagnostics"
```

---

## Phase 2: Devcontainer Script Changes

### Task 6: Python binary installer

**Files:**
- Create: `.devcontainer/scripts/install_corvia.py`

- [ ] **Step 1: Create the installer script**

Create `.devcontainer/scripts/install_corvia.py`:

```python
#!/usr/bin/env python3
"""Install or update the corvia binary from GitHub Releases.

Uses only Python stdlib (no pip dependencies). Supports:
- gh CLI (authenticated, preferred)
- GitHub REST API via urllib (unauthenticated fallback)
- Offline fallback (skip if binary exists)
"""
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import urllib.error

GH_REPO = "chunzhe10/corvia"
INSTALL_DIR = "/usr/local/bin"
TAG_FILE = "/usr/local/share/corvia-release-tag"
BINARY_NAME = "corvia"


def detect_arch() -> str:
    machine = platform.machine()
    if machine in ("x86_64", "AMD64"):
        return "amd64"
    if machine in ("aarch64", "arm64"):
        return "arm64"
    print(f"error: unsupported architecture: {machine}", file=sys.stderr)
    sys.exit(1)


def installed_tag() -> str | None:
    try:
        with open(TAG_FILE) as f:
            return f.read().strip() or None
    except FileNotFoundError:
        return None


def latest_tag_gh() -> str | None:
    """Get latest release tag via gh CLI."""
    try:
        out = subprocess.check_output(
            ["gh", "release", "view", "--repo", GH_REPO, "--json", "tagName", "-q", ".tagName"],
            text=True, timeout=15, stderr=subprocess.DEVNULL,
        )
        return out.strip() or None
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        return None


def latest_tag_api() -> str | None:
    """Get latest release tag via GitHub REST API."""
    url = f"https://api.github.com/repos/{GH_REPO}/releases/latest"
    try:
        req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
            return data.get("tag_name")
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return None


def download_gh(tag: str, asset_name: str, dest: str) -> bool:
    """Download asset via gh CLI."""
    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            subprocess.check_call(
                ["gh", "release", "download", tag, "--repo", GH_REPO,
                 "--pattern", asset_name, "--dir", tmpdir],
                timeout=120, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            src = os.path.join(tmpdir, asset_name)
            if os.path.isfile(src):
                shutil.copy2(src, dest)
                return True
    except (subprocess.CalledProcessError, FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return False


def download_api(tag: str, asset_name: str, dest: str) -> bool:
    """Download asset via GitHub REST API."""
    url = f"https://api.github.com/repos/{GH_REPO}/releases/tags/{tag}"
    try:
        req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
        assets = data.get("assets", [])
        match = next((a for a in assets if a["name"] == asset_name), None)
        if not match:
            return False
        download_url = match["browser_download_url"]
        urllib.request.urlretrieve(download_url, dest)
        return True
    except (urllib.error.URLError, json.JSONDecodeError, StopIteration, TimeoutError):
        return False


def main() -> None:
    arch = detect_arch()
    asset_name = f"corvia-cli-linux-{arch}"
    current_tag = installed_tag()
    binary_path = os.path.join(INSTALL_DIR, BINARY_NAME)

    # Get latest tag.
    latest = latest_tag_gh() or latest_tag_api()

    if latest is None:
        if os.path.isfile(binary_path):
            print(f"  network unavailable, using existing binary ({current_tag or 'unknown'})")
            return
        print("error: cannot determine latest release (no network) and no binary installed",
              file=sys.stderr)
        sys.exit(1)

    if current_tag == latest:
        print(f"  corvia {latest}: up to date")
        return

    # Download.
    print(f"  downloading corvia {latest}...")
    with tempfile.NamedTemporaryFile(delete=False, suffix=f".{asset_name}") as tmp:
        tmp_path = tmp.name

    try:
        if not download_gh(latest, asset_name, tmp_path):
            if not download_api(latest, asset_name, tmp_path):
                if os.path.isfile(binary_path):
                    print(f"  download failed, using existing binary ({current_tag or 'unknown'})")
                    return
                print("error: failed to download corvia binary", file=sys.stderr)
                sys.exit(1)

        # Install.
        os.chmod(tmp_path, 0o755)
        # Use sudo if we can't write directly.
        dest = os.path.join(INSTALL_DIR, BINARY_NAME)
        try:
            shutil.move(tmp_path, dest)
        except PermissionError:
            subprocess.check_call(["sudo", "cp", tmp_path, dest])
            subprocess.check_call(["sudo", "chmod", "755", dest])
            os.unlink(tmp_path)

        # Write tag.
        tag_dir = os.path.dirname(TAG_FILE)
        try:
            os.makedirs(tag_dir, exist_ok=True)
            with open(TAG_FILE, "w") as f:
                f.write(latest)
        except PermissionError:
            subprocess.check_call(
                ["sudo", "bash", "-c", f"mkdir -p {tag_dir} && echo '{latest}' > {TAG_FILE}"]
            )

        print(f"  corvia {latest}: installed")

    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Make executable**

Run: `chmod +x .devcontainer/scripts/install_corvia.py`

- [ ] **Step 3: Verify syntax**

Run: `python3 -m py_compile .devcontainer/scripts/install_corvia.py`
Expected: no output (no syntax errors).

- [ ] **Step 4: Commit**

```bash
git add .devcontainer/scripts/install_corvia.py
git commit -m "feat: add standalone Python binary installer for corvia"
```

---

### Task 7: Trim lib.sh

**Files:**
- Modify: `.devcontainer/scripts/lib.sh`

Remove all functions that depend on `corvia-dev`, `tools/`, or ORT provider management.
Keep auth forwarding, plugin install, and utility functions.

- [ ] **Step 1: Remove dead functions from lib.sh**

Remove these functions entirely:
- `_corvia_dev_python()` (lines 122-130)
- `_ensure_corvia_dev()` (lines 134-145)
- `install_binaries()` (lines 150-166)
- `ensure_corvia()` (lines 286-315)
- `ensure_ort_provider_libs()` (lines 595-605)
- `install_python_editable()` (lines 387-412)
- `ensure_tooling()` (lines 652-659)
- `install_extension()` (lines 170-200)
- `fix_workspace_perms()` (lines 321-328)
- `clone_into_nonempty()` (lines 334-351)
- `pre_clone_repos()` (lines 355-374)
- `init_workspace()` (lines 377-381)
- `create_gpu_symlinks()` (lines 611-649)

Also remove the `# Ensure uv/uvx are on PATH` block (lines 89-91) since we no longer
need Python package installation.

- [ ] **Step 2: Verify syntax**

Run: `bash -n .devcontainer/scripts/lib.sh`
Expected: no output (no syntax errors).

- [ ] **Step 3: Commit**

```bash
git add .devcontainer/scripts/lib.sh
git commit -m "refactor: remove dead functions from lib.sh (corvia-dev, ORT, tooling)"
```

---

### Task 8: Rewrite post-create.sh

**Files:**
- Modify: `.devcontainer/scripts/post-create.sh`

- [ ] **Step 1: Replace entire script**

Replace `.devcontainer/scripts/post-create.sh` with:

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

echo "=== Corvia Workspace: post-create ==="

step "Waiting for network"
wait_for_network || exit 1

step "Forwarding GitHub credentials"
forward_gh_auth

step "Installing corvia binary"
python3 "$SCRIPT_DIR/install_corvia.py"

step "Initializing corvia"
corvia init --yes

step "Installing VS Code extensions"
EXT_DIR="$WORKSPACE_ROOT/.devcontainer/extensions/corvia-services"
VSIX="$EXT_DIR/corvia-services-$(python3 -c "import json; print(json.load(open('$EXT_DIR/package.json'))['version'])" 2>/dev/null || echo "0.0.0").vsix"
if [ -f "$VSIX" ]; then
    install_vsix_direct "$VSIX"
elif [ -f "$EXT_DIR/package.json" ] && command -v vsce >/dev/null 2>&1; then
    printf "    building extension"
    if (cd "$EXT_DIR" && vsce package --no-dependencies) >/dev/null 2>&1; then
        echo " done"
        VSIX=$(ls -t "$EXT_DIR"/*.vsix 2>/dev/null | head -1)
        [ -n "$VSIX" ] && install_vsix_direct "$VSIX"
    else
        echo " FAILED"
    fi
else
    echo "    no .vsix found — build with: cd $EXT_DIR && vsce package --no-dependencies"
fi

echo ""
echo "=== post-create complete ==="
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n .devcontainer/scripts/post-create.sh`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add .devcontainer/scripts/post-create.sh
git commit -m "refactor: simplify post-create.sh (binary install + corvia init)"
```

---

### Task 9: Rewrite post-start.sh

**Files:**
- Modify: `.devcontainer/scripts/post-start.sh`

- [ ] **Step 1: Replace entire script**

Replace `.devcontainer/scripts/post-start.sh` with:

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

# ── 1/4 ───────────────────────────────────────────────────────────────
step "Forwarding host authentication"
forward_host_auth

# ── 2/4 ───────────────────────────────────────────────────────────────
step "corvia health check"
if command -v corvia >/dev/null 2>&1; then
    corvia init --yes || fail_msg "corvia init failed"
else
    fail_msg "corvia not on PATH — run post-create or install manually"
fi

# ── 3/4 ───────────────────────────────────────────────────────────────
step "Claude Code integration"
printf "    superpowers plugin: "
install_claude_plugin "https://github.com/obra/superpowers.git" superpowers claude-plugins-official \
    || fail_msg "git clone failed — check network connectivity"

# ── 4/4 ───────────────────────────────────────────────────────────────
# Sweep cargo build artifacts if disk is >70% full.
"$SCRIPT_DIR/sweep-cargo-cache.sh" || true

echo ""
echo "Ready."
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n .devcontainer/scripts/post-start.sh`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add .devcontainer/scripts/post-start.sh
git commit -m "refactor: simplify post-start.sh (auth + corvia init + plugin)"
```

---

### Task 10: Simplify Taskfile.yml

**Files:**
- Modify: `.devcontainer/Taskfile.yml`

- [ ] **Step 1: Replace Taskfile.yml**

Replace `.devcontainer/Taskfile.yml` with:

```yaml
# Devcontainer setup orchestration — simplified for corvia v2.
#
# Entry points:
#   task post-start    — called by setup_wrapper.py on every container connect
#   task post-create   — called by setup_wrapper.py on container creation
#
# Inspect:
#   task --list        — show all tasks
#   task --dry <task>  — dry-run (show what would execute)

version: '3'

vars:
  WORKSPACE_ROOT: '{{.WORKSPACE_ROOT | default "/workspaces/corvia-workspace"}}'
  SCRIPT_DIR: '{{.WORKSPACE_ROOT}}/.devcontainer/scripts'

set: [e, u, pipefail]
silent: true

env:
  TZ: Asia/Kuala_Lumpur
  CORVIA_WORKSPACE: '{{.WORKSPACE_ROOT}}'

# ═══════════════════════════════════════════════════════════════════════
# POST-START — runs on every container connect
# ═══════════════════════════════════════════════════════════════════════

tasks:
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

  post-start:auth:
    desc: "Forward host authentication (gh + claude)"
    cmds:
      - cmd: 'source {{.SCRIPT_DIR}}/lib.sh && log auth "forwarding credentials" && forward_host_auth'

  post-start:corvia-init:
    desc: "Run corvia health check (idempotent)"
    status:
      - corvia init --yes --format json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d['status']=='ok' else 1)" 2>/dev/null
    cmds:
      - |
        source {{.SCRIPT_DIR}}/lib.sh
        if command -v corvia >/dev/null 2>&1; then
          logg services "running corvia init"
          corvia init --yes
        else
          logw services "corvia not on PATH — run post-create first"
        fi

  post-start:claude-integration:
    desc: "Install superpowers plugin"
    cmds:
      - |
        source {{.SCRIPT_DIR}}/lib.sh
        logm claude "superpowers: installing"
        install_claude_plugin "https://github.com/obra/superpowers.git" superpowers claude-plugins-official \
          || logw claude "superpowers: FAILED (check network)"

  post-start:ensure-extensions:
    desc: "Ensure VS Code extensions installed"
    status:
      - |
        EXT_DIR="{{.WORKSPACE_ROOT}}/.devcontainer/extensions/corvia-services"
        VERSION=$(python3 -c "import json; print(json.load(open('$EXT_DIR/package.json'))['version'])" 2>/dev/null || echo "0.0.0")
        EXT_ID="corvia.corvia-services-$VERSION"
        test -d "/root/.vscode-server/extensions/$EXT_ID" -o -d "/root/.vscode-server-insiders/extensions/$EXT_ID"
    cmds:
      - |
        source {{.SCRIPT_DIR}}/lib.sh
        EXT_DIR="{{.WORKSPACE_ROOT}}/.devcontainer/extensions/corvia-services"
        VSIX=$(ls -t "$EXT_DIR"/*.vsix 2>/dev/null | head -1)
        if [ -n "$VSIX" ]; then
          logm vscode "extension: installing $(basename "$VSIX")"
          install_vsix_direct "$VSIX"
        else
          logw vscode "extension: no .vsix found"
        fi

  post-start:sweep:
    desc: "Sweep cargo cache if disk pressure"
    cmds:
      - '{{.SCRIPT_DIR}}/sweep-cargo-cache.sh || true'

  # ═══════════════════════════════════════════════════════════════════
  # POST-CREATE — runs once on container creation
  # ═══════════════════════════════════════════════════════════════════

  post-create:
    desc: "Full post-create sequence (devcontainer lifecycle)"
    cmds:
      - cmd: "printf '\\033[1m=== Corvia Workspace: post-create ===\\033[0m\\n'"
      - task: post-create:network
      - task: post-create:gh-auth
      - task: post-create:install-binary
      - task: post-create:corvia-init
      - task: post-create:vscode-extensions
      - cmd: echo ""
      - cmd: 'echo "=== post-create complete ==="'

  post-create:network:
    desc: "Wait for network connectivity"
    status:
      - curl -fsL --max-time 2 https://github.com >/dev/null 2>&1
    cmds:
      - cmd: 'source {{.SCRIPT_DIR}}/lib.sh && log network "waiting for connectivity"'
      - cmd: 'source {{.SCRIPT_DIR}}/lib.sh && wait_for_network'

  post-create:gh-auth:
    desc: "Forward GitHub credentials"
    status:
      - gh auth status >/dev/null 2>&1
    cmds:
      - cmd: 'source {{.SCRIPT_DIR}}/lib.sh && log auth "forwarding GitHub credentials"'
      - cmd: 'source {{.SCRIPT_DIR}}/lib.sh && forward_gh_auth'

  post-create:install-binary:
    desc: "Install corvia binary from GitHub Releases"
    status:
      - test -x /usr/local/bin/corvia
    cmds:
      - cmd: 'source {{.SCRIPT_DIR}}/lib.sh && logg install "installing corvia"'
      - python3 {{.SCRIPT_DIR}}/install_corvia.py

  post-create:corvia-init:
    desc: "Initialize corvia workspace"
    status:
      - test -d {{.WORKSPACE_ROOT}}/.corvia/index
    cmds:
      - cmd: 'source {{.SCRIPT_DIR}}/lib.sh && logg workspace "initializing"'
      - corvia init --yes

  post-create:vscode-extensions:
    desc: "Install VS Code extensions"
    cmds:
      - cmd: 'source {{.SCRIPT_DIR}}/lib.sh && logm vscode "installing extensions"'
      - |
        source {{.SCRIPT_DIR}}/lib.sh
        EXT_DIR="{{.WORKSPACE_ROOT}}/.devcontainer/extensions/corvia-services"
        VSIX="$EXT_DIR/corvia-services-$(python3 -c "import json; print(json.load(open('$EXT_DIR/package.json'))['version'])" 2>/dev/null || echo "0.0.0").vsix"
        if [ -f "$VSIX" ]; then
          install_vsix_direct "$VSIX"
        elif [ -f "$EXT_DIR/package.json" ] && command -v vsce >/dev/null 2>&1; then
          printf "    building extension"
          if (cd "$EXT_DIR" && vsce package --no-dependencies) >/dev/null 2>&1; then
            echo " done"
            VSIX=$(ls -t "$EXT_DIR"/*.vsix 2>/dev/null | head -1)
            [ -n "$VSIX" ] && install_vsix_direct "$VSIX"
          else
            echo " FAILED"
          fi
        else
          echo "    no .vsix found — build with: cd $EXT_DIR && vsce package --no-dependencies"
        fi
```

- [ ] **Step 2: Verify task syntax**

Run: `task --list -d .devcontainer 2>&1 | head -20`
Expected: lists post-start and post-create tasks without errors. If `task` binary
is not available, verify with: `python3 -c "import yaml; yaml.safe_load(open('.devcontainer/Taskfile.yml'))"` (or just check that it parses).

- [ ] **Step 3: Commit**

```bash
git add .devcontainer/Taskfile.yml
git commit -m "refactor: simplify Taskfile.yml (remove service management, use corvia init)"
```

---

### Task 11: Simplify init-host.sh

**Files:**
- Modify: `.devcontainer/scripts/init-host.sh`

Remove port allocation, port manifest, ollama sidecar passthrough, compose profiles,
and `.env` generation. Keep GPU detection and Docker compose override for device
passthrough.

- [ ] **Step 1: Remove port allocation section**

In `init-host.sh`, remove everything from the `# ── Port allocation` comment
(line 108) through the `find_free_port` calls (lines 108-176). This includes
the `port_in_use`, `find_free_port` functions and the `HOST_API`, `HOST_VITE`,
`HOST_INFERENCE`, `HOST_OLLAMA` assignments.

- [ ] **Step 2: Remove port mappings from compose override generation**

In the compose override generation section, remove the `ports:` block for the
`app` service (lines 244-248):

```yaml
    ports:
      - "$HOST_API:8020"
      - "$HOST_VITE:8021"
      - "$HOST_INFERENCE:8030"
```

- [ ] **Step 3: Remove ollama sidecar section**

Remove the entire `# ── Ollama sidecar GPU passthrough` section (lines 322-353).

- [ ] **Step 4: Remove compose profiles and .env generation**

Remove the `# ── Compose profiles from workspace flags` section (lines 356-368)
which writes `.env` with `COMPOSE_PROFILES`.

- [ ] **Step 5: Remove port manifest**

Remove the `# ── Port manifest + summary` section (lines 370-389) which writes
`.port-manifest.json` and prints port URLs.

- [ ] **Step 6: Add cleanup of stale files**

Add before the final summary:

```bash
# ── Clean up stale files from v1 ────────────────────────────────────
rm -f "$DC_DIR/.port-manifest.json"
# Only remove .env if it only contains COMPOSE_PROFILES (v1 artifact).
if [ -f "$DC_DIR/.env" ] && grep -qx "COMPOSE_PROFILES=.*" "$DC_DIR/.env" 2>/dev/null; then
    line_count=$(wc -l < "$DC_DIR/.env")
    if [ "$line_count" -le 3 ]; then
        rm -f "$DC_DIR/.env"
    fi
fi
```

- [ ] **Step 7: Update summary output**

Replace the port summary with a simpler GPU-only summary:

```bash
echo "GPU: $GPU_SUMMARY"
echo ""
echo "Host init complete."
```

- [ ] **Step 8: Verify syntax**

Run: `bash -n .devcontainer/scripts/init-host.sh`
Expected: no output.

- [ ] **Step 9: Commit**

```bash
git add .devcontainer/scripts/init-host.sh
git commit -m "refactor: remove port allocation and ollama from init-host.sh"
```

---

### Task 12: Update devcontainer.json and .mcp.json

**Files:**
- Modify: `.devcontainer/devcontainer.json`
- Modify: `.mcp.json`
- Modify: `.gitignore`

- [ ] **Step 1: Update devcontainer.json**

Remove the `forwardPorts` line and update comments:

```json
    // No ports to forward — corvia v2 uses stdio MCP (no HTTP server).
    // Ollama (11434) is on the sidecar container if coding-llm is enabled.
```

Also remove the `corvia.serverUrl` setting from VS Code customizations since there
is no HTTP server.

- [ ] **Step 2: Update .mcp.json**

Replace `.mcp.json` content:

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

- [ ] **Step 3: Update .gitignore**

Replace the v1 `.corvia/` entries (lines 4-14) with:

```gitignore
# corvia data directory (derived data ignored via .corvia/.gitignore)
# To share knowledge with your team, do NOT add .corvia/ here —
# .corvia/.gitignore already excludes derived data (index, models, traces).
# Only entries/ and corvia.toml are tracked.
```

Remove stale entries that reference v1 paths:
- `.corvia/hnsw/`
- `.corvia/hnsw_index/`
- `.corvia/lite_store.redb`
- `.corvia/coordination.redb`
- `.corvia/coordination.redb.lock`
- `.corvia/staging/`
- `.corvia/knowledge/devcontainer-telemetry/`

Also remove `.devcontainer/.port-manifest.json` and `.devcontainer/.env` lines
since those files are cleaned up by init-host.sh.

- [ ] **Step 4: Commit**

```bash
git add .devcontainer/devcontainer.json .mcp.json .gitignore
git commit -m "chore: update devcontainer.json, .mcp.json, .gitignore for corvia v2"
```

---

### Task 13: Fix setup_telemetry.py

**Files:**
- Modify: `.devcontainer/scripts/setup_telemetry.py`

Replace the HTTP MCP call in `_mcp_write` with a `corvia write` subprocess call.

- [ ] **Step 1: Replace `_mcp_write` function**

Replace the `_mcp_write` function (lines 310-346) with:

```python
def _mcp_write(content: str) -> bool:
    """Write telemetry to corvia via CLI subprocess."""
    try:
        result = subprocess.run(
            ["corvia", "write", content, "--kind", "learning"],
            capture_output=True, text=True, timeout=30,
            cwd=os.environ.get("CORVIA_WORKSPACE", "/workspaces/corvia-workspace"),
        )
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False
```

- [ ] **Step 2: Remove `_mcp_url` function**

Remove the `_mcp_url` function (lines 30-38) which reads the API port from
`corvia.toml` — no longer needed.

- [ ] **Step 3: Verify syntax**

Run: `python3 -m py_compile .devcontainer/scripts/setup_telemetry.py`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add .devcontainer/scripts/setup_telemetry.py
git commit -m "fix: replace HTTP MCP call with corvia write subprocess in telemetry"
```

---

### Task 14: Remove dangling corvia-dev symlink

**Files:**
- System file: `/usr/local/bin/corvia-dev`

- [ ] **Step 1: Remove the broken symlink**

Run: `sudo rm -f /usr/local/bin/corvia-dev`

This is a symlink to `tools/corvia-dev/.venv/bin/corvia-dev` which no longer exists.

- [ ] **Step 2: Verify**

Run: `ls -la /usr/local/bin/corvia-dev 2>&1`
Expected: `No such file or directory`

- [ ] **Step 3: No commit needed** (system file, not tracked in git)

---

### Task 15: Integration test — end-to-end verification

**Files:**
- No new files (manual verification)

- [ ] **Step 1: Test corvia init from scratch**

```bash
cd /tmp && mkdir test-project && cd test-project
git init
corvia init --yes
```

Expected:
- `.corvia/` directory created
- `.corvia/corvia.toml` with defaults
- `.corvia/version` with `1.0.0`
- `.corvia/.gitignore` with derived data exclusions
- `.mcp.json` created with stdio entry

- [ ] **Step 2: Test idempotent re-run**

```bash
corvia init --yes
```

Expected: "all checks passed", no modifications.

- [ ] **Step 3: Test corvia mcp --test**

```bash
cd /tmp/test-project
corvia mcp --test
```

Expected: prints config, model, tools, status. (May fail if models not downloaded
in test environment — that's expected and the error message should be clear.)

- [ ] **Step 4: Test v1 config migration**

```bash
cd /tmp && mkdir test-v1 && cd test-v1
git init
echo '[embedding]\nmodel = "custom"\nreranker_model = "custom"' > corvia.toml
corvia init --yes
```

Expected:
- `corvia.toml` renamed to `corvia.toml.v1-backup`
- `.corvia/corvia.toml` has the custom config

- [ ] **Step 5: Clean up**

```bash
rm -rf /tmp/test-project /tmp/test-v1
```

- [ ] **Step 6: Verify devcontainer scripts parse cleanly**

```bash
bash -n .devcontainer/scripts/post-start.sh
bash -n .devcontainer/scripts/post-create.sh
bash -n .devcontainer/scripts/lib.sh
bash -n .devcontainer/scripts/init-host.sh
python3 -m py_compile .devcontainer/scripts/setup_telemetry.py
python3 -m py_compile .devcontainer/scripts/install_corvia.py
```

Expected: all clean (no output).

- [ ] **Step 7: Commit any fixes discovered during testing**

---

## Dependency Graph

```
Task 1 (discover) ──→ Task 2 (config) ──→ Task 3 (CLI commands) ──→ Task 5 (mcp --test)
                                      └──→ Task 4 (init) ──────────→ Task 15 (e2e test)
                                                                  ↗
Task 6 (Python installer) ──→ Task 8 (post-create) ──────────────→ Task 15
Task 7 (lib.sh) ──→ Task 8 (post-create) ──→ Task 9 (post-start) → Task 15
                └──→ Task 10 (Taskfile) ──────────────────────────→ Task 15
Task 11 (init-host) ─────────────────────────────────────────────→ Task 15
Task 12 (devcontainer.json + .mcp.json + .gitignore) ────────────→ Task 15
Task 13 (setup_telemetry) ──────────────────────────────────────→ Task 15
Task 14 (dangling symlink) ─────────────────────────────────────→ Task 15
```

Phase 1 (Tasks 1-5): Rust changes, sequential.
Phase 2 (Tasks 6-14): Devcontainer changes, mostly parallel except lib.sh must precede scripts.
Task 15: Integration testing after both phases.
