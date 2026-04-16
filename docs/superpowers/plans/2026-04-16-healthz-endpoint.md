# GET /healthz Endpoint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `GET /healthz` to the corvia HTTP server that returns 200 + `{"ok":true,"entries":N}` when the index is queryable, or 503 + `{"ok":false,"error":"..."}` if not.

**Architecture:** One new async handler `healthz_handler` in `mcp.rs`, registered alongside `POST /mcp`. The handler calls the existing `handle_status_with_handles` function (line 517) and wraps its result in a JSON response. No new state, no new files, no new dependencies.

**Tech Stack:** Rust, axum 0.7, serde_json (already imported), tempfile (already in dev-deps)

---

### Task 1: Write the failing test

**Files:**
- Modify: `repos/corvia/crates/corvia-cli/src/mcp.rs` — add test inside `#[cfg(test)] mod http_tests`

- [ ] **Step 1: Add the test to the `http_tests` module**

Open `repos/corvia/crates/corvia-cli/src/mcp.rs` and add this test at the end of the `http_tests` module (before the closing `}`  at line 991):

```rust
    #[test]
    fn healthz_core_logic_returns_entry_count_for_empty_index() {
        let dir = tempfile::tempdir().unwrap();
        let config = Config::default();
        let redb = RedbIndex::open(&dir.path().join("store.redb")).unwrap();
        let tantivy = TantivyIndex::open(&dir.path().join("tantivy")).unwrap();

        let result = handle_status_with_handles(&config, dir.path(), &redb, &tantivy);
        assert!(result.is_ok(), "handle_status_with_handles failed: {:?}", result);
        let val = result.unwrap();
        assert_eq!(
            val["entry_count"].as_u64().unwrap_or(999),
            0,
            "expected 0 entries in a fresh index"
        );
    }
```

- [ ] **Step 2: Run the test to confirm it compiles and passes**

```bash
cd /workspaces/corvia-workspace/repos/corvia
cargo test -p corvia-cli healthz_core_logic 2>&1 | tail -20
```

Expected output: `test http_tests::healthz_core_logic_returns_entry_count_for_empty_index ... ok`

> Note: This test verifies the logic `healthz_handler` will call. It passes now because `handle_status_with_handles` exists. The handler itself doesn't exist yet — that's Task 2.

---

### Task 2: Implement the handler and register the route

**Files:**
- Modify: `repos/corvia/crates/corvia-cli/src/mcp.rs`
  - Line 14: add `get` to routing import
  - After line 515 (`fn handle_tools_list_http`): add `healthz_handler`
  - Line 808: add `.route("/healthz", get(healthz_handler))`

- [ ] **Step 1: Add `get` to the routing import**

Find this line (line 14):
```rust
    routing::post,
```
Change it to:
```rust
    routing::{get, post},
```

- [ ] **Step 2: Add the `healthz_handler` function**

Find the block ending at approximately line 514:
```rust
    serde_json::json!({ "tools": tools })
}
```

Insert the following immediately after it (before the next `///` doc comment):

```rust
/// `GET /healthz` — deep health check. Queries the live index handles and returns
/// `{"ok":true,"entries":N}` on success or `{"ok":false,"error":"..."}` with a 503
/// if the index is unreadable.
async fn healthz_handler(State(state): State<ServeState>) -> Response {
    match handle_status_with_handles(
        &state.config,
        &state.base_dir,
        &state.handles.redb,
        &state.handles.tantivy,
    ) {
        Ok(status) => {
            let entries = status["entry_count"].as_u64().unwrap_or(0);
            (StatusCode::OK, Json(json!({"ok": true, "entries": entries}))).into_response()
        }
        Err(e) => (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"ok": false, "error": e.to_string()})),
        )
            .into_response(),
    }
}
```

- [ ] **Step 3: Register the route in the router**

Find this block (around line 807):
```rust
    let app = Router::new()
        .route("/mcp", post(mcp_post_handler))
        .layer(axum::extract::DefaultBodyLimit::max(1024 * 1024))
        .with_state(state);
```

Change it to:
```rust
    let app = Router::new()
        .route("/mcp", post(mcp_post_handler))
        .route("/healthz", get(healthz_handler))
        .layer(axum::extract::DefaultBodyLimit::max(1024 * 1024))
        .with_state(state);
```

- [ ] **Step 4: Build to verify no compilation errors**

```bash
cd /workspaces/corvia-workspace/repos/corvia
cargo build -p corvia-cli 2>&1 | tail -20
```

Expected: `Compiling corvia-cli ...` then `Finished`. No errors.

---

### Task 3: Run all tests

**Files:** No changes — verify only.

- [ ] **Step 1: Run the full corvia-cli test suite**

```bash
cd /workspaces/corvia-workspace/repos/corvia
cargo test -p corvia-cli 2>&1 | tail -30
```

Expected:
```
test http_tests::healthz_core_logic_returns_entry_count_for_empty_index ... ok
test http_tests::initialize_response_has_required_fields ... ok
test http_tests::notification_detection_identifies_notifications_correctly ... ok
test http_tests::tools_list_response_has_four_tools ... ok
test result: ok. 4 passed; 0 failed
```

All 4 tests must pass. If any fail, fix before proceeding.

---

### Task 4: Commit

- [ ] **Step 1: Stage and commit the changes**

```bash
cd /workspaces/corvia-workspace
git add repos/corvia/crates/corvia-cli/src/mcp.rs
git commit -m "feat: add GET /healthz deep-check endpoint

Returns 200 {\"ok\":true,\"entries\":N} when the index is queryable,
or 503 {\"ok\":false,\"error\":\"...\"} if index reads fail.

Enables devcontainer startup scripts to poll:
  until curl -sf http://127.0.0.1:8020/healthz; do sleep 0.5; done"
```

Expected: `[feat/healthz-endpoint <sha>] feat: add GET /healthz deep-check endpoint`
