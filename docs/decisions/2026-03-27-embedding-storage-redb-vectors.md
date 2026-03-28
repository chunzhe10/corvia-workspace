# Strip Embeddings from JSON, Store in Redb VECTORS Table

> **Status**: Approved (5-persona review complete 2026-03-27)
> **Supersedes**: `2026-03-19-json-embedding-exclusion-design.md`
> **Branch**: TBD

## Problem

Each `.corvia/knowledge/{scope}/{uuid}.json` stores a 768-dim embedding as a JSON float array.
At 14,682 entries this creates:

- **232 MB** on disk (92% is embedding text)
- Unreadable git diffs (768 floats change on every re-embed)
- **30-60s rebuild** (parse 14K JSON files from disk)
- Scales to **1.6 GB** at 100K entries (LiteStore target)

## Decision

1. Strip embeddings from JSON files (content + metadata only)
2. Store embeddings in a dedicated **Redb VECTORS table** with raw f32 bytes
3. Rebuild reads from VECTORS table, not JSON files

### Why Redb Over a Custom Binary Sidecar

A custom binary sidecar (`.corvia/vectors/{scope}.bin`) was evaluated and rejected:

| Concern | Custom Sidecar | Redb |
|---------|---------------|------|
| Crash safety | Must implement (fsync, partial write recovery) | Built-in ACID transactions |
| Concurrency | Must implement (flock, torn writes) | Built-in MVCC |
| Compaction | Must implement (tombstones, write-then-rename) | Automatic page reuse |
| Alignment | Must ensure (bytemuck + mmap alignment) | Handled internally |
| Code cost | ~500-1000 lines | ~30 lines |
| Rebuild 100K | ~0.1-0.2s | ~0.3-0.5s |

The 0.2s rebuild difference does not justify 500+ lines of crash-safety and compaction code.
Redb is already a dependency with battle-tested ACID guarantees.

## Design

### 1. New Redb Table

```rust
const VECTORS: TableDefinition<&[u8; 16], &[u8]> = TableDefinition::new("vectors");
// Key: UUID as 16 raw bytes
// Value: 768 * 4 = 3072 bytes (raw f32 little-endian, native endian)
```

### 2. Write Path (in existing `index_entry_into` transaction)

```rust
// Inside the existing write transaction in index_entry_into():
let uuid_bytes = entry.id.as_bytes();
let vec_bytes: &[u8] = bytemuck::cast_slice(embedding);
vectors_table.insert(uuid_bytes, vec_bytes)?;
```

No new transaction — piggybacks on the existing write txn that already touches
ENTRIES, SCOPE_INDEX, HNSW_TO_UUID, UUID_TO_HNSW, and SOURCE_VERSION_INDEX.

### 3. Read Path (rebuild_from_files replacement)

```rust
// New: rebuild_from_vectors()
for item in vectors_table.iter()? {
    let (key, value) = item?;
    let uuid = Uuid::from_bytes(*key.value());
    let embedding: &[f32] = bytemuck::cast_slice(value.value());
    hnsw.insert((embedding, hnsw_id));
}
```

### 4. JSON Serialization Change

In `corvia-common/src/types.rs`:
```rust
#[serde(skip_serializing)]
#[serde(default)]  // backward compat: old JSON with embeddings still parses
pub embedding: Option<Vec<f32>>,
```

### 5. Migration

**Two-phase** (safe ordering):

Phase 1 — Populate VECTORS table:
- Read all JSON files via `read_all()`
- For each entry with `embedding: Some(vec)`, write to VECTORS table
- Verify VECTORS table entry count matches expected count

Phase 2 — Strip JSON files:
- Re-serialize each JSON file (embedding field now skipped)
- Only executes after Phase 1 verification passes

**Lazy fallback**: On read, if JSON has embedding but VECTORS table entry missing,
write to VECTORS table on the fly. Handles stragglers and gradual migration.

**Idempotent**: Safe to re-run. Checks each entry: if VECTORS has it, skip.
If JSON has embedding but VECTORS doesn't, migrate it.

### 6. Backward Compatibility

- Old JSON files with `embedding` field: parse correctly via `#[serde(default)]`
- Old binaries reading new JSON (no embedding): entry has `embedding: None`,
  triggers re-embed on rebuild (existing behavior for entries without embeddings)
- Preserve old read path for **one major version** before removing

### 7. Delete / Scope Cleanup

- `delete_scope()`: already removes ENTRIES, SCOPE_INDEX, HNSW mappings.
  Add: remove all VECTORS entries for the scope (range scan by scope prefix,
  or delete individually from the UUID set collected from SCOPE_INDEX).
- Individual entry delete: remove from VECTORS table in same transaction.

## Files Changed

| File | Change |
|------|--------|
| `corvia-common/src/types.rs` | `#[serde(skip_serializing)]` on `embedding` |
| `corvia-kernel/src/lite_store.rs` | Add VECTORS table definition, write in `index_entry_into`, new `rebuild_from_vectors()`, delete in `delete_scope()` |
| `corvia-kernel/src/knowledge_files.rs` | No change (JSON read/write unchanged, embedding just absent) |
| `corvia-cli/src/main.rs` | Add `migrate-vectors` subcommand |
| `.corvia/.gitignore` | No change needed (Redb already gitignored) |

## Impact

| Metric | Before | After |
|--------|--------|-------|
| JSON file size (avg) | ~15 KB | ~1.2 KB |
| Total git-tracked (14.7K) | 232 MB | ~18 MB |
| Total git-tracked (100K) | 1.6 GB | ~120 MB |
| Rebuild time (14.7K) | ~10-20s (JSON parse) | ~0.1s (Redb scan) |
| Rebuild time (100K) | ~30-60s | ~0.3-0.5s |
| Git diff readability | Useless (float noise) | Meaningful (content only) |
| Redb file size increase | - | +43 MB (14.7K) / +380 MB (100K) |

## Risks

- **Redb file growth**: VECTORS table adds ~380-440 MB at 100K entries. Acceptable
  for a gitignored ephemeral cache. `corvia rebuild` can regenerate from content.
- **Fresh clone**: No embeddings in JSON or Redb after clone. `corvia rebuild` must
  re-embed from content (requires inference server). Document expected time.
- **Model change**: If embedding dimensions change, VECTORS table has stale data.
  Detect dimension mismatch on startup → force rebuild.

## Review History

5-persona review (2026-03-27):
- **Senior SWE**: Recommended Redb over custom sidecar. Flagged `skip_serializing` data loss during transition.
- **Product Manager**: Approved — strengthens git-trackable value prop. Requires rollback path + migration UX.
- **QA Engineer**: 5 blocking issues (concurrency, corruption, rollback, fresh clone, migration resume). All resolved by Redb choice.
- **Storage/Data Engineer**: Custom sidecar has crash-safety gaps (header atomicity, torn writes, compaction). Redb eliminates all.
- **Security Engineer**: Validate scope_id on vector paths. Use `try_cast_slice`. Two-phase migration. Set restrictive permissions.
