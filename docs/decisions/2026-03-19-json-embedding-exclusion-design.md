# JSON Embedding Exclusion Design

> **Status**: Design (needs 3-persona review before implementation)
> **Motivation**: Architecture challenge finding — embeddings dominate JSON file size
> (~80%) and create terrible git diffs (768 floats per entry).

## Problem

Each `.corvia/knowledge/{scope}/{uuid}.json` file stores:
- `content`: the actual text (small, human-readable, git-diffable)
- `metadata`: source_file, language, chunk_type, etc. (small)
- `embedding`: `Option<Vec<f32>>` — 768 floats × 4 bytes = 3KB per entry

For 8,769 entries: ~26MB of embedding data in JSON files. The embeddings:
- Create massive git diffs (every number changes on re-embed)
- Are always recomputable from `content` via the inference engine
- Are already stored in HNSW index and Redb metadata

## Proposed Change

Stop writing `embedding` to JSON files. Store it only in HNSW + Redb.

### What Changes

1. **Serialization**: When writing JSON to disk, set `embedding: None`
2. **Deserialization**: When reading JSON, `embedding` remains `Option<Vec<f32>>` (None)
3. **Ingest pipeline**: After reading from JSON, re-embed if needed (lazy, on-demand)
4. **`corvia rebuild`**: Already re-embeds from content — no change needed
5. **HNSW + Redb**: Continue storing embeddings as before — they're the cache
6. **Backward compatibility**: Old JSON files with embeddings still parse fine (Option field)

### What Doesn't Change

- `KnowledgeEntry` struct — `embedding` field stays as `Option<Vec<f32>>`
- HNSW index — still stores vectors
- Redb metadata — still maps entry_id → hnsw_id
- `corvia rebuild` — already handles re-embedding from scratch
- Search/retrieval — reads from HNSW, not JSON

### Migration

No migration needed. New entries save without embeddings. Old entries with
embeddings continue to work. Over time, as entries are superseded, the
embedding data naturally disappears from JSON.

For immediate cleanup: `corvia rebuild --strip-embeddings` (optional future command).

## Impact

| Metric | Before | After |
|--------|--------|-------|
| Avg JSON file size | ~3.5KB | ~0.5KB |
| Total .corvia/ size | ~30MB | ~5MB |
| Git diff per re-ingest | Massive (float arrays) | Minimal (content only) |
| `corvia rebuild` required? | No (embeddings in JSON) | Yes (must re-embed) |

## Risk

- **`corvia rebuild` becomes mandatory after fresh clone**: Without embeddings in
  JSON, a fresh `git clone` + `corvia rebuild` must re-embed all entries. This is
  already the documented workflow.
- **Rebuild time**: Re-embedding 8,769 entries at 22ms each ≈ 3 minutes. Acceptable.
- **No rollback**: Once embeddings are excluded, old JSON files without embeddings
  can't be used without re-embedding. But `corvia rebuild` handles this.

## Implementation

Single change in `lite_store.rs` — when writing the JSON file, clone the entry
and set `embedding = None`:

```rust
// In write_json_file():
let mut disk_entry = entry.clone();
disk_entry.embedding = None; // Don't persist embeddings to JSON
serde_json::to_writer_pretty(&file, &disk_entry)?;
```

## Review Required

This change affects the data model's persistence contract. Needs 3-persona
deep review before implementation.
