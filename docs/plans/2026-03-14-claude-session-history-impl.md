# Claude Session History — Implementation Plan

> **Status:** Complete

**Goal:** Record every Claude Code session as structured history, ingest into a personal `user-history` scope, and auto-promote product-relevant entries to `corvia` scope via LLM classification. Includes workstream (git branch) filtering as a kernel prerequisite.

**Architecture:** Five hook events → JSONL append log → gzip on session end → adapter ingests to `user-history` scope → classify-queue heuristic → LLM classifier promotes to `corvia` scope. Live dashboard visibility via inotify session watcher. Graph edges link subagent sessions to parents.

**Tech Stack:** Rust (hooks, adapter, kernel, server), JSONL (event log), gRPC (embedding), REST (classification trigger)

**Spec:** `repos/corvia/docs/rfcs/2026-03-14-claude-session-history-design.md`

---

## File Structure

### Delivered (Phases 1-3)

| Action | File | Status |
|--------|------|--------|
| Created | `crates/corvia-cli/src/hooks/session.rs` (520 lines) | **SHIPPED** — 5 event types, O_APPEND writes, gzip, ingest trigger |
| Created | `adapters/corvia-adapter-claude-sessions/rust/src/main.rs` (943 lines) | **SHIPPED** — full ingest pipeline, classify-queue population, archive |
| Created | `crates/corvia-server/src/dashboard/session_watcher.rs` (953 lines) | **SHIPPED** — inotify + polling, real-time state tracking, SSE broadcast |
| Created | `crates/corvia-kernel/src/session_manager.rs` (295 lines) | **SHIPPED** — state machine, Redb persistence, stale/orphan detection |
| Modified | `crates/corvia-kernel/src/chunking_strategy.rs` | **SHIPPED** — `SourceMetadata` extended with `workstream`, `content_role`, `source_origin` |
| Modified | `crates/corvia-server/src/rest.rs:965-1130` | **SHIPPED** — LLM classification endpoint, atomic queue rewrite, promotion pipeline |
| Modified | `corvia.toml` | **SHIPPED** — `user-history` scope with 180-day TTL |
| Modified | `.claude/settings.json` | **SHIPPED** — hooks wired for all 5 event types |

### Remaining (Phase 4: Graph Edges + Polish)

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `repos/corvia/adapters/corvia-adapter-claude-sessions/rust/src/main.rs` | Add `spawned_by` graph edge creation after subagent session ingest |
| Modify | `repos/corvia/crates/corvia-server/src/mcp.rs` | Add `workstream` param to `corvia_ask` / `corvia_context` tool schemas (follow-on from shipped filter) |

---

## Phase 1: Session Recording Hooks — SHIPPED

**Delivered in:** `crates/corvia-cli/src/hooks/session.rs`

| Task | Status | Notes |
|------|--------|-------|
| `session_start` event recording | Done | Detects agent_type from stdin, reads `CORVIA_AGENT_ID` env var |
| `user_prompt` event with turn counter | Done | Scans last 8KB for current turn number |
| `tool_start` / `tool_end` events | Done | Nanosecond timestamps, input stripping, 500-char output truncation |
| `session_end` with gzip + ingest trigger | Done | Atomic temp→rename, REST POST with 3x retry |
| O_APPEND atomic writes | Done | Under PIPE_BUF (4096) for concurrency safety |
| 9 tests | Done | Truncation, JSON schema, event recording |

---

## Phase 2: Adapter + Classification — SHIPPED

**Delivered in:** `adapters/corvia-adapter-claude-sessions/rust/src/main.rs` + `crates/corvia-server/src/rest.rs`

| Task | Status | Notes |
|------|--------|-------|
| Session discovery (*.jsonl.gz) | Done | Reads `.ingested` state file, skips processed |
| JSONL parsing with gzip | Done | Groups events by turn into BTreeMap |
| Turn-level chunking (1 entry per turn) | Done | Structured text: USER / TOOLS / RESPONSE |
| `content_role` inference | Done | `"research"` for subagent search+read patterns, else `"session-turn"` |
| `source_origin` population | Done | `"claude:main"` or `"claude:subagent"` |
| Classify-queue heuristic (repo path detection) | Done | Appends entry IDs with repo paths to `.classify-queue` |
| Archive management | Done | Moves processed .jsonl.gz to `archive/` |
| LLM classification endpoint | Done | `classify_sessions()` in rest.rs:965-1130 |
| Atomic queue rewrite | Done | Temp file → rename, failed entries retry |
| Promotion to `corvia` scope | Done | YES entries copied with inferred `content_role` |
| 14 adapter tests + 6 classification tests | Done | Parse, format, ingest, archive, promotion, batching |

---

## Phase 3: Live Dashboard + Session Manager — SHIPPED

**Delivered in:** `session_watcher.rs` + `session_manager.rs`

| Task | Status | Notes |
|------|--------|-------|
| inotify file watcher with polling fallback | Done | 2s poll interval, 200ms debounce |
| Real-time session state tracking | Done | Turn count, active tool, tools used, duration |
| SSE broadcast to frontend | Done | `HookSessionUpdate` events |
| Stale detection (10min) and eviction (60min) | Done | LRU with MAX_SESSIONS=500 |
| Session manager state machine | Done | Created→Active→Committing→Merging→Closed + Stale/Orphaned/Recoverable |
| Redb persistence | Done | JSON serialization, query by agent |
| 16 watcher tests + 10 manager tests | Done | State machines, symlink rejection, partial line handling |

---

## Phase 4: Graph Edges + Polish — PARTIALLY DONE

Workstream filter (originally Task 4.1) was shipped 2026-03-17. Env var spike (originally Task 4.3) is resolved — hooks use stdin `agent_id` field as primary detection, falling back to `CORVIA_AGENT_ID` env var. Remaining work: graph edges and workstream filter extension to `corvia_ask`/`corvia_context`.

### Task 4.1: Workstream filter — SHIPPED

Implemented in `rag_types.rs`, `retriever.rs` (3 call sites + oversample), `rest.rs`, `mcp.rs` (`corvia_search`).
Tests: `test_post_filter_by_workstream`, `test_post_filter_workstream_combined_with_role`.

**Follow-on:** Extend workstream param to `corvia_ask` and `corvia_context` MCP tool schemas (currently only `corvia_search`).

### Task 4.2: Graph edges for subagent sessions — SHIPPED

**Implementation:**
- Adapter (`main.rs`): Added `parent_session_id` to `SourceMetadata`, set only on turn-1 entries
- Kernel (`chunking_strategy.rs`): Added `parent_session_id` field to `SourceMetadata` struct
- CLI (`workspace.rs`): After storing session entries, builds `session_id → first_entry_id` lookup,
  creates `spawned_by` edges for subagent sessions. Cross-batch parents logged as deferred.
- Tests: `test_subagent_parent_session_id_on_turn_1_only`, `test_main_session_no_parent_id`

### Task 4.3: Env var spike — RESOLVED

Hooks use stdin JSON `agent_id` field for subagent detection (lines 136-159 of session.rs).
`CORVIA_AGENT_ID` env var used for user identity. Claude Code does not currently expose
`CLAUDE_CODE_IS_SUBAGENT` or `CLAUDE_CODE_PARENT_SESSION_ID` — the stdin-based approach
is the correct implementation.

### Task 4.4: Extend workstream filter to `corvia_ask` / `corvia_context` — SHIPPED

Added `workstream` parameter to both MCP tool schemas and wired through to `RetrievalOpts`
in `tool_corvia_context()` and `tool_corvia_ask()` handlers. 150 server tests pass.

---

## Test Strategy

| Component | Approach | Status |
|-----------|----------|--------|
| Hook event recording | Unit: JSON schema, truncation, turn counter | **DONE** (9 tests) |
| Adapter ingest pipeline | Unit + Integration: parse, format, archive, state file | **DONE** (14 tests) |
| LLM classification | Unit: empty queue, promotion, batching, failure retry | **DONE** (6 tests) |
| Session watcher | Unit: state machine, partial lines, symlink rejection | **DONE** (16 tests) |
| Session manager | Unit: create, transition, heartbeat, listing | **DONE** (10 tests) |
| Workstream filter | Unit: post_filter with workstream match/mismatch/None | **DONE** (2 tests) |
| Graph edges | Unit: parent_session_id on turn-1 only, main has none | **DONE** (2 tests) |
| Env var detection | Manual: log env vars in main + subagent contexts | **RESOLVED** (stdin-based) |
| End-to-end | Manual: full session → gzip → ingest → search → promote cycle | **TODO** |

---

## Open Questions (from design spec Section 11)

| Item | Status | Notes |
|------|--------|-------|
| `Stop` hook response capture | Deferred | Claude Code may not expose response text; design degrades gracefully |
| Env var names for subagent detection | **RESOLVED** | Hooks use stdin `agent_id` field; `CORVIA_AGENT_ID` for user identity |
| TTL enforcement in kernel | Future | `ttl_days` is metadata only today |
| Scoped GC CLI (`corvia gc --scope`) | Future | Deletion via REST API + `corvia rebuild` |
| Per-scope HNSW indices | Future | Permanent fix for cross-scope HNSW pollution |
| Workstream filter in `corvia_ask`/`corvia_context` | Follow-on after Task 4.1 | Extend to all RAG tools, not just `corvia_search` |

---

## Summary

| Phase | Scope | Status | Effort |
|-------|-------|--------|--------|
| 1 | Session recording hooks | **SHIPPED** | — |
| 2 | Adapter + classification pipeline | **SHIPPED** | — |
| 3 | Live dashboard + session manager | **SHIPPED** | — |
| 4.1 | Kernel workstream filter | **SHIPPED** | — |
| 4.2 | Graph edges (spawned_by) | **SHIPPED** | — |
| 4.3 | Env var research spike | **RESOLVED** | — |
| 4.4 | Workstream in corvia_ask/corvia_context | **SHIPPED** | — |
