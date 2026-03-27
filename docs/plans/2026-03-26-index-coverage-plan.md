# Implementation Plan: Dashboard Index Coverage & Staleness Detection

> **Status:** Complete — corvia#10 (implementation) + corvia#11 (review cleanup)

**Date**: 2026-03-26
**Spec**: `repos/corvia/docs/rfcs/2026-03-26-dashboard-index-coverage-design.md` (rev 2)
**Issue**: corvia-workspace#18

## Goal

Add `index_coverage`, `index_stale`, and supporting fields to `GET /api/dashboard/status`
so the dashboard and automation can detect when the HNSW index is stale or incomplete.
Three-layer comparison: disk files vs Redb store vs HNSW vector index.

## Architecture

```
corvia.toml [dashboard] section
        ↓ (config load)
DashboardSection { stale_threshold, coverage_ttl_secs }
        ↓ (server startup)
IndexCoverageCache (Arc<tokio::sync::Mutex<_>> on AppState)
        ↓ (status_handler / refresh endpoint)
CoverageSnapshot → DashboardStatusResponse fields
```

Three count sources:
- **disk_count**: `.json` files in `{data_dir}/knowledge/{scope_id}/` (via spawn_blocking)
- **store_count**: Redb SCOPE_INDEX entries (via `store.count()`)
- **hnsw_count**: Redb HNSW_TO_UUID entries (via new `LiteStore::hnsw_entry_count()`)

## Tech Stack

- Rust (async/await, tokio)
- Redb (HNSW_TO_UUID table scan)
- axum (route handler, JSON response)
- chrono (UTC timestamps)
- serde (serialization)
- tracing (observability)

---

## Task 1: Add `DashboardSection` to config

**Files:**
- Modify: `crates/corvia-common/src/config.rs`

**Step 1: Add the struct and defaults (after `HooksConfig` impl, ~line 106)**

```rust
fn default_stale_threshold() -> f64 { 0.9 }
fn default_coverage_ttl() -> u64 { 60 }
const MIN_COVERAGE_TTL: u64 = 5;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DashboardSection {
    #[serde(default = "default_stale_threshold")]
    pub stale_threshold: f64,
    #[serde(default = "default_coverage_ttl")]
    pub coverage_ttl_secs: u64,
}

impl Default for DashboardSection {
    fn default() -> Self {
        Self {
            stale_threshold: 0.9,
            coverage_ttl_secs: 60,
        }
    }
}

impl DashboardSection {
    /// Validate and clamp values. Call after deserialization.
    pub fn validate(&mut self) -> Result<()> {
        if !(0.0..=1.0).contains(&self.stale_threshold) {
            return Err(CorviaError::Config(format!(
                "dashboard.stale_threshold must be 0.0..=1.0, got {}",
                self.stale_threshold
            )));
        }
        if self.coverage_ttl_secs < MIN_COVERAGE_TTL {
            tracing::warn!(
                "dashboard.coverage_ttl_secs={} below minimum {}, clamping",
                self.coverage_ttl_secs, MIN_COVERAGE_TTL
            );
            self.coverage_ttl_secs = MIN_COVERAGE_TTL;
        }
        Ok(())
    }
}
```

**Step 2: Wire into `CorviaConfig` (after `hooks` field, ~line 156)**

```rust
#[serde(default)]
pub dashboard: DashboardSection,
```

**Step 3: Add to `CorviaConfig::default()` (after `hooks: None`, ~line 539)**

```rust
dashboard: DashboardSection::default(),
```

**Step 4: Add to `CorviaConfig::postgres_default()` if it exists — same default.**

- [ ] Struct and defaults added
- [ ] Wired into CorviaConfig
- [ ] Default impls updated
- [ ] `validate()` method implemented

---

## Task 2: Add `hnsw_entry_count()` to LiteStore

**Files:**
- Modify: `crates/corvia-kernel/src/lite_store.rs`

**Step 1: Add method to `impl LiteStore` (after `flush_hnsw`, ~line 355)**

```rust
/// Count entries in the HNSW_TO_UUID table (entries with vector embeddings).
/// This may differ from `count()` (SCOPE_INDEX) if HNSW was rebuilt or corrupted.
pub fn hnsw_entry_count(&self) -> Result<u64> {
    let read_txn = self.db.begin_read()
        .map_err(|e| CorviaError::Storage(format!("Failed to begin read txn: {e}")))?;
    let table = read_txn.open_table(HNSW_TO_UUID)
        .map_err(|e| CorviaError::Storage(format!("Failed to open HNSW_TO_UUID: {e}")))?;
    let count = table.len()
        .map_err(|e| CorviaError::Storage(format!("Failed to count HNSW_TO_UUID: {e}")))?;
    Ok(count)
}
```

Note: `redb::Table::len()` returns a `u64` count of table entries — this is a
metadata read, not a full scan.

- [ ] `hnsw_entry_count()` method added
- [ ] Returns count from HNSW_TO_UUID table

---

## Task 3: Add coverage fields to `DashboardStatusResponse`

**Files:**
- Modify: `crates/corvia-common/src/dashboard.rs`

**Step 1: Add fields to `DashboardStatusResponse` (after `traces` field, ~line 78)**

```rust
/// Coverage ratio: HNSW entries / knowledge files on disk.
/// null when disk_count == 0 (fresh workspace).
pub index_coverage: Option<f64>,
/// true when coverage < threshold. null when coverage is null.
pub index_stale: Option<bool>,
/// Knowledge JSON files on disk for the default scope.
pub index_disk_count: u64,
/// Entries in Redb SCOPE_INDEX for the default scope.
pub index_store_count: u64,
/// Entries in Redb HNSW_TO_UUID table.
pub index_hnsw_count: u64,
/// Configured staleness threshold (0.0-1.0).
pub index_stale_threshold: f64,
/// ISO 8601 timestamp of last coverage computation.
pub index_coverage_checked_at: Option<String>,
```

- [ ] 7 new fields added to response struct

---

## Task 4: Create `IndexCoverageCache` module

**Files:**
- Create: `crates/corvia-server/src/dashboard/coverage.rs`
- Modify: `crates/corvia-server/src/dashboard/mod.rs` (add `pub mod coverage;`)

**Step 1: Create `coverage.rs` with the cache struct**

```rust
use std::path::Path;
use std::time::{Duration, Instant};
use tracing::{debug, info, warn};

use corvia_kernel::knowledge_files;
use corvia_kernel::traits::QueryableStore;
use corvia_kernel::lite_store::LiteStore;

/// Snapshot of coverage state returned to callers.
#[derive(Debug, Clone)]
pub struct CoverageSnapshot {
    pub coverage: Option<f64>,
    pub stale: Option<bool>,
    pub disk_count: u64,
    pub store_count: u64,
    pub hnsw_count: u64,
    pub threshold: f64,
    pub checked_at: Option<String>,
}

pub struct IndexCoverageCache {
    snapshot: CoverageSnapshot,
    last_computed: Option<Instant>,
    ttl: Duration,
    threshold: f64,
}

impl IndexCoverageCache {
    pub fn new(threshold: f64, ttl_secs: u64) -> Self {
        Self {
            snapshot: CoverageSnapshot {
                coverage: None,
                stale: None,
                disk_count: 0,
                store_count: 0,
                hnsw_count: 0,
                threshold,
                checked_at: None,
            },
            last_computed: None,
            ttl: Duration::from_secs(ttl_secs),
            threshold,
        }
    }

    /// Return cached snapshot if TTL is valid, otherwise recompute.
    pub async fn get(
        &mut self,
        data_dir: &Path,
        scope_id: &str,
        store: &dyn QueryableStore,
    ) -> CoverageSnapshot {
        if let Some(last) = self.last_computed {
            if last.elapsed() < self.ttl {
                debug!(
                    disk = self.snapshot.disk_count,
                    hnsw = self.snapshot.hnsw_count,
                    "index coverage cache hit"
                );
                return self.snapshot.clone();
            }
        }
        self.recompute(data_dir, scope_id, store).await
    }

    /// Force recompute regardless of TTL.
    pub async fn refresh(
        &mut self,
        data_dir: &Path,
        scope_id: &str,
        store: &dyn QueryableStore,
    ) -> CoverageSnapshot {
        self.recompute(data_dir, scope_id, store).await
    }

    async fn recompute(
        &mut self,
        data_dir: &Path,
        scope_id: &str,
        store: &dyn QueryableStore,
    ) -> CoverageSnapshot {
        let start = Instant::now();

        // Disk count via spawn_blocking (avoid blocking async runtime)
        let scope_dir = knowledge_files::scope_dir(data_dir, scope_id);
        let disk_count = tokio::task::spawn_blocking(move || {
            count_json_files(&scope_dir)
        })
        .await
        .unwrap_or_else(|e| {
            warn!("spawn_blocking for disk count failed: {e}");
            0
        });

        // Store count (Redb SCOPE_INDEX)
        let store_count = store.count(scope_id).await.unwrap_or_else(|e| {
            warn!("store.count failed: {e}");
            0
        });

        // HNSW count (Redb HNSW_TO_UUID)
        let hnsw_count = if let Some(lite) = store.as_any().downcast_ref::<LiteStore>() {
            lite.hnsw_entry_count().unwrap_or_else(|e| {
                warn!("hnsw_entry_count failed: {e}");
                0
            })
        } else {
            // PostgresStore: pgvector manages its own index, use store_count
            store_count
        };

        // Compute coverage
        let (coverage, stale) = if disk_count == 0 {
            (None, None)
        } else {
            let ratio = (hnsw_count as f64 / disk_count as f64).min(1.0);
            (Some(ratio), Some(ratio < self.threshold))
        };

        // Orphan detection
        if hnsw_count > disk_count || store_count > disk_count {
            warn!(
                disk = disk_count,
                store = store_count,
                hnsw = hnsw_count,
                "index has more entries than knowledge files on disk (orphaned entries)"
            );
        }

        let checked_at = chrono::Utc::now().to_rfc3339();
        let elapsed_ms = start.elapsed().as_millis();

        info!(
            disk = disk_count,
            store = store_count,
            hnsw = hnsw_count,
            ?coverage,
            ?stale,
            compute_ms = elapsed_ms,
            "index coverage recomputed"
        );

        self.snapshot = CoverageSnapshot {
            coverage,
            stale,
            disk_count,
            store_count,
            hnsw_count,
            threshold: self.threshold,
            checked_at: Some(checked_at),
        };
        self.last_computed = Some(Instant::now());

        self.snapshot.clone()
    }
}

/// Count `.json` files in a directory (non-recursive).
/// Returns 0 if the directory does not exist or is unreadable.
fn count_json_files(dir: &Path) -> u64 {
    if !dir.exists() {
        return 0;
    }
    match std::fs::read_dir(dir) {
        Ok(entries) => entries
            .filter_map(|e| e.ok())
            .filter(|e| {
                e.path()
                    .extension()
                    .and_then(|ext| ext.to_str())
                    .map_or(false, |ext| ext == "json")
            })
            .count() as u64,
        Err(e) => {
            warn!("Failed to read knowledge dir {}: {e}", dir.display());
            0
        }
    }
}
```

**Step 2: Add `pub mod coverage;` to `dashboard/mod.rs` (at top, with other mods)**

- [ ] `coverage.rs` created with `IndexCoverageCache`, `CoverageSnapshot`, `count_json_files`
- [ ] Module declared in `dashboard/mod.rs`

---

## Task 5: Wire cache into `AppState` and `status_handler`

**Files:**
- Modify: `crates/corvia-server/src/rest.rs`
- Modify: `crates/corvia-server/src/dashboard/mod.rs`

**Step 1: Add field to `AppState` (after `hook_sessions`, ~line 61)**

```rust
/// Cached index coverage metrics (TTL-based, async-safe).
pub coverage_cache: Arc<tokio::sync::Mutex<crate::dashboard::coverage::IndexCoverageCache>>,
```

**Step 2: Update `status_handler` in `dashboard/mod.rs` (~line 104-165)**

After the existing `merge_queue_depth` computation and before building the response,
add:

```rust
// Index coverage (cached, recomputed on TTL expiry)
let coverage = {
    let mut cache = state.coverage_cache.lock().await;
    cache.get(&state.data_dir, scope_id, &*state.store).await
};
```

Then update the `Json(DashboardStatusResponse { ... })` construction to include:

```rust
index_coverage: coverage.coverage,
index_stale: coverage.stale,
index_disk_count: coverage.disk_count,
index_store_count: coverage.store_count,
index_hnsw_count: coverage.hnsw_count,
index_stale_threshold: coverage.threshold,
index_coverage_checked_at: coverage.checked_at,
```

**Step 3: Add refresh route to dashboard router (in `pub fn router`, ~line 85)**

```rust
.route("/api/dashboard/status/refresh-coverage", post(refresh_coverage_handler))
```

**Step 4: Implement refresh handler (after `status_handler`)**

```rust
/// POST /api/dashboard/status/refresh-coverage
/// Force-recompute coverage and return fresh snapshot.
async fn refresh_coverage_handler(
    State(state): State<Arc<AppState>>,
) -> Json<serde_json::Value> {
    let scope_id = state
        .default_scope_id
        .as_deref()
        .unwrap_or(DEFAULT_SCOPE_ID);

    let snapshot = {
        let mut cache = state.coverage_cache.lock().await;
        cache.refresh(&state.data_dir, scope_id, &*state.store).await
    };

    Json(serde_json::json!({
        "index_coverage": snapshot.coverage,
        "index_stale": snapshot.stale,
        "index_disk_count": snapshot.disk_count,
        "index_store_count": snapshot.store_count,
        "index_hnsw_count": snapshot.hnsw_count,
        "index_stale_threshold": snapshot.threshold,
        "index_coverage_checked_at": snapshot.checked_at,
    }))
}
```

- [ ] `coverage_cache` added to `AppState`
- [ ] `status_handler` updated to include coverage fields
- [ ] Refresh route added to router
- [ ] `refresh_coverage_handler` implemented

---

## Task 6: Initialize cache at server startup

**Files:**
- Modify: wherever `AppState` is constructed (search for `AppState {` in `rest.rs` or `main.rs`)

**Step 1: Find AppState construction site**

```bash
grep -n "AppState {" crates/corvia-server/src/rest.rs crates/corvia-cli/src/main.rs
```

**Step 2: After reading config, create the cache**

```rust
let dashboard_cfg = config.dashboard.clone();
// Validate will have been called at config load time already
let coverage_cache = Arc::new(tokio::sync::Mutex::new(
    crate::dashboard::coverage::IndexCoverageCache::new(
        dashboard_cfg.stale_threshold,
        dashboard_cfg.coverage_ttl_secs,
    ),
));
```

**Step 3: Add to `AppState` struct literal**

```rust
coverage_cache,
```

**Step 4: Perform initial cache population after server starts**

```rust
// Populate coverage cache on startup
{
    let mut cache = coverage_cache.lock().await;
    let scope_id = config.project.scope_id.as_str();
    let _ = cache.get(&data_dir, scope_id, &*store).await;
}
```

- [ ] Cache created from config values
- [ ] Added to AppState construction
- [ ] Initial population on startup

---

## Task 7: Add `dashboard` to hot-reload allowlist

**Files:**
- Modify: `crates/corvia-kernel/src/ops.rs`
- Modify: `crates/corvia-server/src/mcp.rs` (description strings only)

**Step 1: Add to `HOT_RELOADABLE_SECTIONS` (~line 127)**

Change:
```rust
const HOT_RELOADABLE_SECTIONS: &[&str] = &["agent_lifecycle", "merge", "rag", "chunking", "reasoning", "adapters", "inference"];
```
To:
```rust
const HOT_RELOADABLE_SECTIONS: &[&str] = &["agent_lifecycle", "merge", "rag", "chunking", "reasoning", "adapters", "inference", "dashboard"];
```

**Step 2: Update MCP tool descriptions in `mcp.rs` (~line 241, 278)**

Add `dashboard` to the listed sections in both `corvia_config_get` and
`corvia_config_set` description strings.

- [ ] `ops.rs` allowlist updated
- [ ] MCP tool descriptions updated

---

## Task 8: Add config validation call

**Files:**
- Modify: wherever config is loaded/parsed (search for `toml::from_str` or
  `CorviaConfig` deserialization in CLI)

**Step 1: Find config load site**

```bash
grep -rn "toml::from_str\|from_str.*CorviaConfig\|load_config" crates/corvia-cli/src/
```

**Step 2: After deserializing, call validate**

```rust
config.dashboard.validate()?;
```

- [ ] Validation wired into config load path

---

## Task 9: Update test_state helper

**Files:**
- Modify: `crates/corvia-server/src/dashboard/mod.rs` (test module, ~line 1459)

**Step 1: Add `coverage_cache` to `test_state` (after `hook_sessions`)**

```rust
coverage_cache: Arc::new(tokio::sync::Mutex::new(
    crate::dashboard::coverage::IndexCoverageCache::new(0.9, 60),
)),
```

- [ ] test_state helper updated

---

## Task 10: Unit tests for `IndexCoverageCache`

**Files:**
- Modify: `crates/corvia-server/src/dashboard/coverage.rs` (add `#[cfg(test)] mod tests`)

Add tests at the bottom of `coverage.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use corvia_kernel::lite_store::LiteStore;
    use corvia_kernel::traits::QueryableStore;
    use tempfile::tempdir;

    async fn make_store(dir: &Path) -> LiteStore {
        let store = LiteStore::open(dir, 3).unwrap();
        store.init_schema().await.unwrap();
        store
    }

    // Helper: write N dummy .json files to knowledge/{scope_id}/
    fn write_dummy_json_files(data_dir: &Path, scope_id: &str, count: u64) {
        let dir = data_dir.join("knowledge").join(scope_id);
        std::fs::create_dir_all(&dir).unwrap();
        for i in 0..count {
            let id = uuid::Uuid::new_v4();
            std::fs::write(dir.join(format!("{id}.json")), format!(r#"{{"dummy":{i}}}"#)).unwrap();
        }
    }
}
```

| Test | Setup | Assert |
|------|-------|--------|
| `test_fresh_workspace_no_files` | empty tempdir, no knowledge dir | coverage=None, stale=None, all counts=0 |
| `test_knowledge_dir_missing` | tempdir exists but no `knowledge/` subdir | coverage=None, stale=None, disk_count=0 |
| `test_full_coverage` | 10 JSON files + 10 entries inserted into store | coverage=1.0, stale=false |
| `test_partial_coverage` | 10 JSON files + 7 entries inserted | coverage=0.7, stale=true (threshold 0.9) |
| `test_threshold_boundary_exact` | coverage exactly == threshold | stale=false (< not <=) |
| `test_threshold_boundary_below` | coverage = threshold - 0.01 | stale=true |
| `test_hnsw_gt_disk_orphaned` | 5 JSON files + 10 entries | coverage=1.0 (clamped), stale=false |
| `test_ttl_returns_cached` | compute, immediately call again | second call returns same checked_at |
| `test_ttl_expired_recomputes` | compute with ttl=0s (use 5s min), wait, call again | different checked_at |
| `test_invalid_json_in_dir` | 10 valid + 2 non-JSON .txt files | disk_count=10 (only .json counted) |
| `test_read_dir_permission_error` | create dir, chmod 000 (if running as non-root) | disk_count=0, no panic |
| `test_count_json_files_empty_dir` | create empty scope dir | disk_count=0 |
| `test_concurrent_access` | spawn 10 tasks calling get() concurrently | no panic, no deadlock |

- [ ] All 13 unit tests implemented and passing

---

## Task 11: Config tests

**Files:**
- Modify: `crates/corvia-common/src/config.rs` (add tests to existing test module, or create one)

| Test | Setup | Assert |
|------|-------|--------|
| `test_dashboard_defaults` | Deserialize config without `[dashboard]` | threshold=0.9, ttl=60 |
| `test_dashboard_partial_override` | Only `stale_threshold = 0.5` set | threshold=0.5, ttl=60 |
| `test_threshold_out_of_range_high` | `stale_threshold = 1.5` | validate() returns Err |
| `test_threshold_out_of_range_negative` | `stale_threshold = -0.1` | validate() returns Err |
| `test_ttl_below_minimum` | `coverage_ttl_secs = 1` | validate() clamps to 5 |

- [ ] All 5 config tests implemented and passing

---

## Task 12: Integration tests

**Files:**
- Modify: `crates/corvia-server/src/dashboard/mod.rs` (test module)

| Test | Setup | Assert |
|------|-------|--------|
| `test_status_includes_coverage_fields` | default test_state | all 7 fields present, coverage=null, stale=null, counts=0 |
| `test_status_coverage_values` | write 10 knowledge files, insert 7 entries | coverage=0.7, stale=true, disk=10, store=7 |
| `test_refresh_returns_values` | POST to refresh endpoint | 200 OK, body contains all coverage fields |
| `test_refresh_forces_recompute` | GET status, POST refresh, GET status | checked_at differs between first and last GET |

- [ ] All 4 integration tests implemented and passing

---

## Task 13: LiteStore tests

**Files:**
- Modify: `crates/corvia-kernel/src/lite_store.rs` (test module)

| Test | Setup | Assert |
|------|-------|--------|
| `test_hnsw_entry_count_empty` | fresh LiteStore | hnsw_entry_count() == 0 |
| `test_hnsw_entry_count_after_insert` | insert 5 entries with embeddings | hnsw_entry_count() == 5 |
| `test_hnsw_entry_count_after_delete` | insert 5, delete 2 | hnsw_entry_count() == 3 |

- [ ] All 3 LiteStore tests implemented and passing

---

## Task 14: Build and verify

**Commands:**
```bash
cargo build --workspace 2>&1 | tail -20
cargo test --workspace 2>&1 | tail -40
```

- [ ] Clean build with no warnings related to new code
- [ ] All existing tests still pass
- [ ] All new tests pass

---

## Task 15: Manual verification

**Commands:**
```bash
# Start server
corvia-dev up --no-foreground

# Check status endpoint has new fields
curl -s http://localhost:8020/api/dashboard/status | python3 -m json.tool | grep index_

# Test refresh endpoint
curl -s -X POST http://localhost:8020/api/dashboard/status/refresh-coverage | python3 -m json.tool

# Verify hot-reload works
corvia config set dashboard stale_threshold 0.5
curl -s http://localhost:8020/api/dashboard/status | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'threshold={d[\"index_stale_threshold\"]}')"
```

Expected output for fresh workspace:
```json
{
  "index_coverage": null,
  "index_stale": null,
  "index_disk_count": 0,
  "index_store_count": 0,
  "index_hnsw_count": 0,
  "index_stale_threshold": 0.9,
  "index_coverage_checked_at": "2026-03-26T..."
}
```

Expected output after ingest:
```json
{
  "index_coverage": 1.0,
  "index_stale": false,
  "index_disk_count": 9847,
  "index_store_count": 9847,
  "index_hnsw_count": 9847,
  "index_stale_threshold": 0.9,
  "index_coverage_checked_at": "2026-03-26T..."
}
```

- [ ] Status endpoint returns expected fields
- [ ] Refresh endpoint works
- [ ] Hot-reload updates threshold
- [ ] Values make sense for current workspace state

---

## Dependency Order

```
Task 1 (config) ──────────────────────────┐
Task 2 (hnsw_entry_count) ────────────────┤
Task 3 (response fields) ─────────────────┼─→ Task 4 (cache module)
                                           │         ↓
                                           ├─→ Task 5 (wire into AppState + handlers)
                                           │         ↓
                                           ├─→ Task 6 (startup init)
                                           │         ↓
Task 7 (hot-reload allowlist) ─────────────┤
Task 8 (config validation) ────────────────┤
                                           ↓
                                    Task 9 (test_state helper)
                                           ↓
                              Tasks 10-13 (tests, parallelizable)
                                           ↓
                              Task 14 (build + verify)
                                           ↓
                              Task 15 (manual verification)
```

Tasks 1, 2, 3 can run in parallel. Tasks 10, 11, 12, 13 can run in parallel.
