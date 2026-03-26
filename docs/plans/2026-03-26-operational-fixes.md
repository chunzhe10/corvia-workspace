# Operational Fixes: Ingestion + Index + Dashboard

> **Status**: Backlogged
> **Priority**: P1 (blocks smooth developer workflow)
> **Context**: Discovered during Phase 3+5 benchmarking (2026-03-26)

## Background

During comparative eval testing, we found three interconnected operational issues
that degrade the developer experience and make graph expansion non-functional
after devcontainer startup.

**Current state after fixes**:
- 14,653 entries indexed, 7,810 graph relations wired
- Graph expansion wins: 19 queries, vector wins: 7, ties: 43
- MRR: 0.790 (target: 0.7), Recall@5: 69.8% (target: 60%)
- Graph adds ~65ms latency but +7.7% Recall@5

## Issue 1: Redb Exclusive Lock — Can't Ingest While Server Running

**Problem**: `corvia workspace ingest` and `corvia serve` both call
`LiteStore::open()` which acquires an exclusive redb file lock. CLI ingest
fails with "Database already open. Cannot acquire lock." when the server is running.

**Impact**: Users must stop the server to ingest. Devcontainer starts the server
in post-start, so `corvia workspace ingest` always fails in normal operation.

**Options**:
- A) CLI detects running server → sends entries via `POST /v1/memories/write`
- B) Server exposes `POST /v1/ingest` endpoint (adapter pipeline runs server-side)
- C) `corvia-dev ingest` command: stop → ingest → restart
- D) Ingest writes to a staging area, server picks up on next request

**Recommendation**: Option C as a quick fix, Option B as the proper solution.

## Issue 2: Zero Graph Edges Until Re-ingest

**Problem**: The initial devcontainer ingest (post-create) may use an adapter
binary that doesn't emit relations, or the wiring code fails silently. Re-ingesting
with the current binary produces 7,810 relations. Users never know edges are missing.

**Investigation needed**:
- Which adapter binary was used during post-create? Was it pre-M4.2?
- Does `wire_pipeline_relations()` log when it finds zero matches?
- Should the adapter emit a summary of relations found?

**Fix**: Ensure post-create uses the release binary (not a stale cached version),
add logging to `wire_pipeline_relations()`, and add a post-ingest health check
that warns if zero relations were created for a codebase.

## Issue 3: Stale HNSW Index Detection

**Problem**: After CLI ingest (when server is stopped), the server's HNSW index
may not reflect all entries. Dashboard showed 7 entries when 9,847 existed.
The auto-rebuild logic exists but doesn't always trigger.

**Fixes**:
- Devcontainer post-start: compare HNSW entry count (via `/api/dashboard/status`)
  vs knowledge file count (`find .corvia/knowledge -name '*.json' | wc -l`).
  If they diverge by >10%, call `corvia_rebuild_index`.
- Dashboard: add `index_coverage` percentage to status endpoint. Show warning
  banner when coverage < 90%.

## Benchmark Baselines (2026-03-26, post-fix)

| Metric | graph_expand | vector | Delta |
|--------|------------:|-------:|------:|
| Recall@5 | 69.8% | 62.1% | +7.7% |
| Recall@10 | 76.3% | 70.0% | +6.3% |
| KW Recall | 77.6% | 72.4% | +5.2% |
| MRR | 0.790 | 0.765 | +2.5% |
| Relevance | 0.753 | 0.697 | +5.6% |
| Latency | 73ms | 8ms | +65ms |
| Entries | 14,653 | — | — |
| Graph relations | 7,810 | — | — |
| Health findings | 9,187 orphaned_node | — | — |

## Follow-on Prompt

```
Implement the operational fixes from docs/plans/2026-03-26-operational-fixes.md.

Three issues to fix:

1. **`corvia-dev ingest` command** (quick fix for Issue 1):
   - Add an `ingest` subcommand to corvia-dev that stops the server, runs
     `corvia workspace ingest`, then restarts. This unblocks re-ingestion
     without manual server management.
   - Location: tools/corvia-dev/

2. **Devcontainer stale index detection** (Issue 3):
   - Add a Taskfile task to post-start that compares HNSW entry count
     (via /api/dashboard/status → entry_count) against knowledge file count
     (find .corvia/knowledge -name "*.json" | wc -l). If they diverge by
     >10%, trigger rebuild via corvia_rebuild_index MCP call.
   - Location: .devcontainer/Taskfile.yml

3. **Dashboard index coverage indicator** (Issue 3):
   - Add `index_coverage` (float, 0-1) and `index_stale` (bool) fields
     to GET /api/dashboard/status response. Compare entry_count against
     file count on disk.
   - Location: repos/corvia/crates/corvia-server/src/dashboard/mod.rs

Constraints:
- Check corvia MCP tools first for prior decisions
- Issue 2 (graph edge investigation) is deferred — just add logging to
  wire_pipeline_relations() so we can diagnose next time
- Run 4-persona review before committing
- Branch + PR workflow
```
