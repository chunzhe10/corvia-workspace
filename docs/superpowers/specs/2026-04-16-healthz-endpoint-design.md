# Design: GET /healthz Endpoint

**Date:** 2026-04-16
**Status:** Approved
**Scope:** `repos/corvia/crates/corvia-cli/src/mcp.rs`

## Problem

The corvia HTTP MCP server currently exposes only `POST /mcp`. Devcontainer startup
scripts have no way to poll until the server is ready to serve requests. The ~1.2s
model-load window means a script that immediately calls the MCP endpoint may fail.

## Solution

Add `GET /healthz` — a deep-check health endpoint that proves the index is queryable,
not just that the port is open.

## Design

### New route

```
GET /healthz
```

Registered alongside `POST /mcp` in the axum `Router` in `serve_http()`.

### Handler: `healthz_handler`

```rust
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

**Reuses** the existing `handle_status_with_handles` function (line 517) — no new
index-reading logic.

### Router change

```rust
// Before
let app = Router::new()
    .route("/mcp", post(mcp_post_handler))
    .layer(axum::extract::DefaultBodyLimit::max(1024 * 1024))
    .with_state(state);

// After
let app = Router::new()
    .route("/mcp", post(mcp_post_handler))
    .route("/healthz", get(healthz_handler))
    .layer(axum::extract::DefaultBodyLimit::max(1024 * 1024))
    .with_state(state);
```

### Import change

```rust
// Before
use axum::routing::post;

// After
use axum::routing::{get, post};
```

## Response Contract

| Status | Body | Meaning |
|--------|------|---------|
| `200 OK` | `{"ok":true,"entries":N}` | Index queryable; N entries indexed |
| `503 Service Unavailable` | `{"ok":false,"error":"..."}` | Index read failed |

## Usage

Devcontainer startup script:
```bash
until curl -sf http://127.0.0.1:8020/healthz; do sleep 0.5; done
```

## Testing

One unit test in `mcp.rs`:
- Call `healthz_handler` with a valid `ServeState` fixture (real temp index).
- Assert HTTP 200 and `ok: true` in response body.

## Non-Goals

- No authentication (consistent with the rest of the server — localhost-only by design).
- No `/readyz` separate from `/healthz` — single endpoint is sufficient.
- No version or build info in the response body (keep it minimal).
