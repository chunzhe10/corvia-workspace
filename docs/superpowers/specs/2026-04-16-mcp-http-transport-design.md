# Design: corvia MCP HTTP Transport

**Date:** 2026-04-16  
**Status:** Approved  
**Branch:** feat/mcp-http-transport

## Problem

corvia's MCP server runs over stdio (`corvia mcp`). This has two hard limitations:

1. **Single client**: stdio = one process at a time. A second Claude Code window, a session observer, or any concurrent tool cannot connect.
2. **Lock contention**: Redb uses `flock(LOCK_EX|LOCK_NB)` and Tantivy writer uses `O_CREAT|O_EXCL`. Two processes opening the same store = immediate failure.

Additionally, the current code opens fresh `RedbIndex` + `TantivyIndex` handles on every tool call (search, write, status, traces), then drops them. This is wasteful and prevents handle reuse.

## Goal

Add an HTTP transport that:
- Holds index handles open for the lifetime of the process
- Allows multiple concurrent clients (read operations fully concurrent, writes serialized)
- Implements MCP Streamable HTTP (2025-06-18 spec) — single POST `/mcp` endpoint
- Does NOT break `corvia mcp` (stdio) — it must still work for single-client use
- Does NOT change the MCP tool interface (same 4 tools: search, write, status, traces)

## Transport Selection

**Chosen: Streamable HTTP (MCP 2025-06-18)** — single POST `/mcp` endpoint.

| Option | Protocol | Claude Code type | Verdict |
|--------|----------|-----------------|---------|
| rmcp `transport-sse-server` | SSE (2024-11-05) | `"type": "sse"` | Rejected — wrong protocol |
| axum POST handler (manual) | Streamable HTTP (2025-06-18) | `"type": "http"` | **Chosen** |

rmcp 0.1.5 has `transport-sse-server` but NOT Streamable HTTP. The task requires `"type": "http"` in `.mcp.json`, which Claude Code implements as Streamable HTTP. The axum approach is simple: accept JSON-RPC POST, route to handlers, return response.

## Architecture

```
corvia serve --port 8020 --host 127.0.0.1
    │
    ├── load Config + Embedder (once, at startup)
    ├── open RedbIndex (once, held open)
    ├── open TantivyIndex (once, held open)
    │
    └── axum router
         └── POST /mcp
              ├── initialize → server capabilities
              ├── notifications/initialized → 204 No Content
              ├── tools/list → 4 tool definitions
              └── tools/call
                   ├── corvia_search → search_with_handles()
                   ├── corvia_write → write_with_handles() [write_lock held]
                   ├── corvia_status → status_with_handles()
                   └── corvia_traces → traces_with_handles()
```

`corvia mcp` (stdio) is unchanged: opens/drops handles per call, single client.

## Concurrency Model

```rust
struct ServeState {
    config: Arc<Config>,
    embedder: Arc<Embedder>,
    base_dir: PathBuf,
    redb: Arc<RedbIndex>,
    tantivy: Arc<TantivyIndex>,
    write_lock: Arc<tokio::sync::Mutex<()>>,
}
```

- **Reads** (search, status, traces): concurrent — both indexes support concurrent reads.
- **Writes**: hold `write_lock` mutex for the duration — one write at a time.

Tantivy's `reload_reader()` after write commit is safe to call concurrently with ongoing searches (Tantivy uses versioned reader snapshots).

## New API in corvia-core

`search.rs` and `write.rs` gain handle-accepting variants that keep the originals intact:

```rust
// search.rs
pub fn search_with_handles(
    config: &Config,
    base_dir: &Path,
    embedder: &Embedder,
    params: &SearchParams,
    redb: &RedbIndex,
    tantivy: &TantivyIndex,
) -> Result<SearchResponse>

// write.rs
pub fn write_with_handles(
    config: &Config,
    base_dir: &Path,
    embedder: &Embedder,
    params: WriteParams,
    redb: &RedbIndex,
    tantivy: &TantivyIndex,
) -> Result<WriteResponse>
```

Existing `search()` and `write()` become thin wrappers that open handles and call the with-handles variants. No breaking changes.

## MCP Streamable HTTP Protocol

Clients POST JSON-RPC to `/mcp`. Server responds with JSON-RPC.

```
POST /mcp HTTP/1.1
Content-Type: application/json

{"jsonrpc":"2.0","id":1,"method":"initialize","params":{...}}
```

```
HTTP/1.1 200 OK
Content-Type: application/json

{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"tools":{}},...}}
```

**Methods handled:**
- `initialize` → server info + capabilities
- `notifications/initialized` → HTTP 202 (no JSON body)
- `tools/list` → list of 4 tool definitions
- `tools/call` → dispatch to tool handler

**Error responses:** Standard JSON-RPC error object with codes from spec.

## CLI Command

```
corvia serve [OPTIONS]

OPTIONS:
    --port <PORT>    HTTP port [default: 8020]
    --host <HOST>    Bind address [default: 127.0.0.1]
```

## Config

`.mcp.json` updated to HTTP:
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

Optional `corvia.toml` server section (backward-compatible):
```toml
[server]
port = 8020
host = "127.0.0.1"
```

## Files Modified

| File | Change |
|------|--------|
| `repos/corvia/Cargo.toml` | Add `axum = { version = "0.7", features = ["tokio"] }` |
| `repos/corvia/crates/corvia-cli/Cargo.toml` | Add `axum.workspace = true` |
| `repos/corvia/crates/corvia-core/src/search.rs` | Add `search_with_handles()` |
| `repos/corvia/crates/corvia-core/src/write.rs` | Add `write_with_handles()` |
| `repos/corvia/crates/corvia-cli/src/mcp.rs` | Add `ServeState`, `serve_http()`, axum handler |
| `repos/corvia/crates/corvia-cli/src/main.rs` | Add `Serve` subcommand |
| `.mcp.json` | Change to `"type": "http"` |

## Testing Plan

1. `corvia serve --port 8020` starts, holds indexes open
2. Two concurrent `curl -X POST http://127.0.0.1:8020/mcp` search requests both succeed
3. Write followed by immediate search returns the new entry
4. `corvia mcp` (stdio) still works standalone
5. Cargo tests pass (`cargo test --workspace`)

## Out of Scope

- TLS / authentication (localhost-only by default)
- SSE streaming responses (tools return JSON, not streams)
- Updating devcontainer to auto-start `corvia serve` (follow-up)
