# MCP HTTP Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `corvia serve` HTTP command that exposes the MCP server over Streamable HTTP (POST `/mcp`), holding index handles open for concurrent access, while keeping `corvia mcp` (stdio) unchanged.

**Architecture:** Add `axum` 0.7 as a workspace dependency; extract `search_with_handles()` and `write_with_handles()` from existing core functions; add a new `ServeState` with persistent `Arc<IndexHandles>` in `mcp.rs`; mount a single POST `/mcp` axum route that handles JSON-RPC dispatch; add `Serve` subcommand to CLI.

**Tech Stack:** Rust, axum 0.7, tokio, rmcp 0.1.5 (unchanged), redb, tantivy.

---

## File Map

| File | Change |
|------|--------|
| `repos/corvia/Cargo.toml` | Add `axum = { version = "0.7", features = ["http1"] }` to `[workspace.dependencies]` |
| `repos/corvia/crates/corvia-cli/Cargo.toml` | Add `axum.workspace = true` to `[dependencies]` |
| `repos/corvia/crates/corvia-core/src/search.rs` | Add `search_with_handles()`, keep `search()` as thin wrapper |
| `repos/corvia/crates/corvia-core/src/write.rs` | Add `write_with_handles()`, keep `write()` as thin wrapper |
| `repos/corvia/crates/corvia-cli/src/mcp.rs` | Add `IndexHandles`, `ServeState`, `serve_http()`, `mcp_post_handler()`, helpers |
| `repos/corvia/crates/corvia-cli/src/main.rs` | Add `Serve` variant to `Command`, add arm in `main()` |
| `.mcp.json` (workspace root) | Change from stdio to HTTP transport |

---

### Task 1: Add axum to workspace dependencies

**Files:**
- Modify: `repos/corvia/Cargo.toml`
- Modify: `repos/corvia/crates/corvia-cli/Cargo.toml`

- [ ] **Step 1: Add axum to workspace Cargo.toml**

In `repos/corvia/Cargo.toml`, in the `[workspace.dependencies]` section, add after the `rmcp` line:

```toml
axum = { version = "0.7", features = ["http1"] }
```

The full `[workspace.dependencies]` section should look like (showing the MCP and async sections):
```toml
# MCP
rmcp = { version = "0.1", features = ["server", "transport-io"] }
axum = { version = "0.7", features = ["http1"] }

# CLI
clap = { version = "4", features = ["derive"] }

# Async
tokio = { version = "1", features = ["full"] }
```

- [ ] **Step 2: Add axum to corvia-cli Cargo.toml**

In `repos/corvia/crates/corvia-cli/Cargo.toml`, in the `[dependencies]` section, add after `rmcp.workspace = true`:

```toml
axum.workspace = true
```

- [ ] **Step 3: Verify it compiles**

```bash
cd /workspaces/corvia-workspace/repos/corvia
cargo build 2>&1 | tail -5
```

Expected: `Finished \`dev\` profile`

- [ ] **Step 4: Commit**

```bash
git add Cargo.toml crates/corvia-cli/Cargo.toml Cargo.lock
git commit -m "feat: add axum 0.7 to workspace dependencies"
```

---

### Task 2: Add `search_with_handles()` to corvia-core

**Files:**
- Modify: `repos/corvia/crates/corvia-core/src/search.rs`

The existing `search()` function (lines 189–489) opens `RedbIndex` and `TantivyIndex` at the top (lines 202–206), then does all the work. We extract the work into `search_with_handles()` which accepts pre-opened handles, and keep `search()` as a thin wrapper that opens and delegates.

- [ ] **Step 1: Write the failing compile-test**

At the bottom of `crates/corvia-core/src/search.rs`, inside the existing `#[cfg(test)] mod tests { ... }` block, add this test after the existing tests:

```rust
#[test]
fn search_with_handles_signature_exists() {
    // Verify search_with_handles is public and has the right signature.
    // This is a compile-time check only.
    let _fn: fn(
        &Config,
        &std::path::Path,
        &crate::embed::Embedder,
        &SearchParams,
        &crate::index::RedbIndex,
        &crate::tantivy_index::TantivyIndex,
    ) -> anyhow::Result<crate::types::SearchResponse> = search_with_handles;
    let _ = _fn; // suppress unused warning
}
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
cargo test -p corvia-core -- search_with_handles_signature_exists 2>&1 | tail -10
```

Expected: compile error — `search_with_handles` not found.

- [ ] **Step 3: Add `search_with_handles()` function**

In `crates/corvia-core/src/search.rs`, add the new public function **before** the existing `search()` function (around line 189, before the `#[tracing::instrument]` attribute on `search`).

The new function takes the same instrument annotation (so it creates its own span when called from the HTTP server path), but accepts pre-opened handles instead of opening them:

```rust
/// Run the hybrid search pipeline with pre-opened index handles.
///
/// Use this when the caller holds persistent index handles (e.g. the HTTP MCP server).
/// For one-shot callers, use [`search`] which opens handles internally.
#[tracing::instrument(name = "corvia.search", skip(config, base_dir, embedder, params, redb, tantivy), fields(
    query_len = params.query.len(),
    limit = params.limit,
    kind_filter = ?params.kind,
    result_count = tracing::field::Empty,
    confidence = tracing::field::Empty,
))]
pub fn search_with_handles(
    config: &Config,
    base_dir: &Path,
    embedder: &Embedder,
    params: &SearchParams,
    redb: &RedbIndex,
    tantivy: &TantivyIndex,
) -> Result<SearchResponse> {
    // Step 2: Cold start check.
    let indexed_count_str = redb
        .get_meta("entry_count")
        .context("reading entry_count from redb meta")?;
    let indexed_count: u64 = indexed_count_str
        .as_deref()
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);

    if indexed_count == 0 {
        info!("cold start: no entries indexed");
        return Ok(SearchResponse {
            results: vec![],
            quality: QualitySignal {
                confidence: Confidence::None,
                suggestion: Some(
                    "No entries indexed. Run 'corvia ingest' first.".to_string(),
                ),
            },
        });
    }

    // Step 3: Drift detection.
    let entries_dir = base_dir.join(config.entries_dir());
    let actual_files = scan_entries(&entries_dir).context("scanning entries for drift detection")?;
    let actual_count = actual_files.len() as u64;
    let stale = actual_count != indexed_count;

    if stale {
        debug!(
            indexed = indexed_count,
            actual = actual_count,
            "index drift detected"
        );
    }

    // Step 4: Oversample if kind filter is set.
    let retrieval_limit = if params.kind.is_some() {
        params.limit * 3
    } else {
        params.limit
    };
    let retrieval_limit = retrieval_limit.max(config.search.reranker_candidates);

    // Step 5: BM25 search.
    let bm25_results = {
        let _span = info_span!("corvia.search.bm25", query = %params.query, result_count = tracing::field::Empty).entered();
        let results = tantivy
            .search(&params.query, params.kind, retrieval_limit)
            .context("BM25 search")?;
        Span::current().record("result_count", results.len());
        debug!(count = results.len(), "BM25 results");
        results
    };

    // Step 6: Vector search.
    let vector_scored = {
        let _span = info_span!("corvia.search.vector", vector_count = tracing::field::Empty, result_count = tracing::field::Empty).entered();
        let query_vector = embedder
            .embed(&params.query)
            .context("embedding search query")?;

        let all_vectors = redb.all_vectors().context("loading all vectors from redb")?;
        let superseded_ids = redb.superseded_ids().context("loading superseded IDs")?;
        Span::current().record("vector_count", all_vectors.len());

        let mut scored: Vec<(String, String, f32)> = Vec::new();
        for (chunk_id, vector) in &all_vectors {
            let entry_id = match redb.chunk_entry_id(chunk_id)? {
                Some(eid) => eid,
                None => continue,
            };
            if superseded_ids.contains(&entry_id) {
                continue;
            }
            if let Some(ref kind_filter) = params.kind {
                if let Ok(Some(chunk_kind_str)) = redb.get_chunk_kind(chunk_id) {
                    if let Ok(chunk_kind) = chunk_kind_str.parse::<Kind>() {
                        if chunk_kind != *kind_filter {
                            continue;
                        }
                    }
                }
            }
            let similarity = Embedder::cosine_similarity(&query_vector, vector);
            scored.push((chunk_id.clone(), entry_id, similarity));
        }
        scored.sort_by(|a, b| b.2.partial_cmp(&a.2).unwrap_or(std::cmp::Ordering::Equal));
        scored.truncate(retrieval_limit);
        Span::current().record("result_count", scored.len());
        debug!(count = scored.len(), "vector results");
        scored
    };

    // Step 7: RRF fusion.
    let fused = {
        let _span = info_span!("corvia.search.fusion", candidate_count = tracing::field::Empty).entered();
        let result = rrf_fusion(&bm25_results, &vector_scored, config.search.rrf_k);
        Span::current().record("candidate_count", result.len());
        debug!(count = result.len(), "fused candidates");
        result
    };

    // Step 8: Take top reranker_candidates.
    let reranker_count = config.search.reranker_candidates.min(fused.len());
    let top_candidates = &fused[..reranker_count];

    // Step 9: Cross-encoder rerank.
    let mut scored_results = {
        let _span = info_span!("corvia.search.rerank", input_count = top_candidates.len(), output_count = tracing::field::Empty).entered();

        let mut candidate_texts: Vec<String> = Vec::with_capacity(top_candidates.len());
        let mut candidate_chunk_ids: Vec<String> = Vec::with_capacity(top_candidates.len());
        let mut candidate_entry_ids: Vec<String> = Vec::with_capacity(top_candidates.len());

        for candidate in top_candidates {
            match tantivy.get_chunk_text(&candidate.chunk_id)? {
                Some(text) => {
                    candidate_texts.push(text);
                    candidate_chunk_ids.push(candidate.chunk_id.clone());
                    candidate_entry_ids.push(candidate.entry_id.clone());
                }
                None => {
                    warn!(
                        chunk_id = %candidate.chunk_id,
                        "chunk text not found in tantivy, skipping"
                    );
                }
            }
        }

        let mut results: Vec<(String, String, f32, String)>;

        if candidate_texts.is_empty() {
            results = vec![];
        } else {
            let text_refs: Vec<&str> = candidate_texts.iter().map(|s| s.as_str()).collect();
            let rerank_limit = params.limit.max(candidate_texts.len());

            match embedder.rerank(&params.query, &text_refs, rerank_limit) {
                Ok(reranked) => {
                    results = Vec::with_capacity(reranked.len());
                    for rr in &reranked {
                        let idx = rr.index;
                        if idx < candidate_chunk_ids.len() {
                            results.push((
                                candidate_chunk_ids[idx].clone(),
                                candidate_entry_ids[idx].clone(),
                                rr.score,
                                candidate_texts[idx].clone(),
                            ));
                        }
                    }
                }
                Err(e) => {
                    warn!(error = %e, "reranker failed, falling back to RRF scores");
                    results = candidate_chunk_ids
                        .iter()
                        .zip(candidate_entry_ids.iter())
                        .zip(candidate_texts.iter())
                        .enumerate()
                        .map(|(i, ((cid, eid), text))| {
                            let rrf_score = if i < top_candidates.len() {
                                top_candidates[i].rrf_score as f32
                            } else {
                                0.0
                            };
                            (cid.clone(), eid.clone(), rrf_score, text.clone())
                        })
                        .collect();
                }
            }
        }

        Span::current().record("output_count", results.len());
        results
    };

    // Deduplicate by entry_id.
    {
        let mut dedup_input: Vec<(String, String, f32)> = scored_results
            .iter()
            .map(|(cid, eid, score, _)| (cid.clone(), eid.clone(), *score))
            .collect();
        deduplicate_by_entry(&mut dedup_input);
        let keep_chunks: std::collections::HashSet<String> =
            dedup_input.iter().map(|(cid, _, _)| cid.clone()).collect();
        scored_results.retain(|(cid, _, _, _)| keep_chunks.contains(cid));
    }

    scored_results.sort_by(|a, b| b.2.partial_cmp(&a.2).unwrap_or(std::cmp::Ordering::Equal));

    // Step 10: Apply min_score filter.
    let pre_min_score_count = scored_results.len();
    if let Some(min) = params.min_score {
        scored_results.retain(|(_, _, score, _)| *score >= min);
    }

    // Step 11: Apply max_tokens budget.
    if let Some(budget) = params.max_tokens {
        let mut token_count = 0usize;
        let mut keep_count = 0usize;
        for (_cid, _eid, _score, text) in &scored_results {
            let words = text.split_whitespace().count();
            let estimated_tokens = (words as f32 * 1.33) as usize;
            if token_count + estimated_tokens > budget && keep_count > 0 {
                break;
            }
            token_count += estimated_tokens;
            keep_count += 1;
        }
        scored_results.truncate(keep_count);
    }

    scored_results.truncate(params.limit);

    // Step 12: Build SearchResult for each.
    let final_scores: Vec<f32> = scored_results.iter().map(|(_, _, s, _)| *s).collect();

    let mut results: Vec<SearchResult> = Vec::with_capacity(scored_results.len());
    for (chunk_id, entry_id, score, content) in scored_results {
        let kind = tantivy
            .get_chunk_kind(&chunk_id)
            .ok()
            .flatten()
            .unwrap_or_default();
        results.push(SearchResult {
            id: entry_id,
            kind,
            score,
            content,
        });
    }

    // Step 13: Quality signal.
    let quality = {
        let _span = info_span!("corvia.search.quality", confidence = tracing::field::Empty, stale).entered();
        let mut q = compute_quality_signal(&final_scores, stale);
        if results.is_empty() && pre_min_score_count > 0 && params.min_score.is_some() {
            q.suggestion = Some(
                "No results above minimum score threshold. Try lowering min_score or broadening your query.".to_string(),
            );
        }
        Span::current().record("confidence", tracing::field::debug(q.confidence));
        q
    };

    Span::current().record("result_count", results.len());
    Span::current().record("confidence", tracing::field::debug(quality.confidence));

    info!(
        results = results.len(),
        confidence = ?quality.confidence,
        "search complete"
    );

    Ok(SearchResponse { results, quality })
}
```

- [ ] **Step 4: Replace `search()` with thin wrapper**

Replace the entire existing `search()` function (the one starting with `#[tracing::instrument(name = "corvia.search"...` and ending at `Ok(SearchResponse { results, quality })`) with this thin wrapper:

```rust
/// Run the hybrid search pipeline, opening index handles internally.
///
/// For callers that hold persistent handles, use [`search_with_handles`] directly.
pub fn search(
    config: &Config,
    base_dir: &Path,
    embedder: &Embedder,
    params: &SearchParams,
) -> Result<SearchResponse> {
    let redb = RedbIndex::open(&base_dir.join(config.redb_path()))
        .context("opening redb index for search")?;
    let tantivy = TantivyIndex::open(&base_dir.join(config.tantivy_dir()))
        .context("opening tantivy index for search")?;
    search_with_handles(config, base_dir, embedder, params, &redb, &tantivy)
}
```

- [ ] **Step 5: Run all tests**

```bash
cargo test -p corvia-core 2>&1 | tail -20
```

Expected: all tests pass including `search_with_handles_signature_exists`.

- [ ] **Step 6: Commit**

```bash
git add crates/corvia-core/src/search.rs
git commit -m "feat(core): add search_with_handles() for persistent index handle reuse"
```

---

### Task 3: Add `write_with_handles()` to corvia-core

**Files:**
- Modify: `repos/corvia/crates/corvia-core/src/write.rs`

Same pattern as Task 2. The existing `write()` function (lines 151–336) resolves paths and ensures directories exist (Steps 1–2), then opens handles. We extract everything after the handle-open into `write_with_handles()`, keeping directory creation in `write()` only (since `serve_http()` creates dirs at startup).

- [ ] **Step 1: Write the failing compile-test**

At the bottom of `crates/corvia-core/src/write.rs`, inside the existing `#[cfg(test)] mod tests { ... }` block, add after the existing tests:

```rust
#[test]
fn write_with_handles_signature_exists() {
    let _fn: fn(
        &crate::config::Config,
        &std::path::Path,
        &crate::embed::Embedder,
        WriteParams,
        &crate::index::RedbIndex,
        &crate::tantivy_index::TantivyIndex,
    ) -> anyhow::Result<crate::types::WriteResponse> = write_with_handles;
    let _ = _fn;
}
```

- [ ] **Step 2: Run test to confirm failure**

```bash
cargo test -p corvia-core -- write_with_handles_signature_exists 2>&1 | tail -10
```

Expected: compile error — `write_with_handles` not found.

- [ ] **Step 3: Add `write_with_handles()` before the existing `write()` function**

Add this function to `crates/corvia-core/src/write.rs` before the existing `write()` function (around line 151):

```rust
/// Write a new knowledge entry using pre-opened index handles.
///
/// Use this when the caller holds persistent index handles (e.g. the HTTP MCP server).
/// Callers must ensure the entries directory and index directory already exist.
/// For one-shot callers, use [`write`] which creates directories and opens handles.
#[tracing::instrument(name = "corvia.write", skip(config, base_dir, embedder, params, redb, tantivy), fields(
    kind = %params.kind,
    content_len = params.content.len(),
    action = tracing::field::Empty,
    superseded_count = tracing::field::Empty,
))]
pub fn write_with_handles(
    config: &Config,
    base_dir: &Path,
    embedder: &Embedder,
    params: WriteParams,
    redb: &RedbIndex,
    tantivy: &TantivyIndex,
) -> Result<WriteResponse> {
    let entries_dir = base_dir.join(config.entries_dir());

    // Step 3: Determine supersedes list and action.
    let caller_provided_supersedes = !params.supersedes.is_empty();
    let mut supersedes = params.supersedes;
    let action: String;
    let mut dedup_similarity: Option<f32> = None;

    if !caller_provided_supersedes && !params.content.is_empty() {
        let _dedup_span = info_span!("corvia.write.dedup",
            threshold = config.search.dedup_threshold,
            matched = tracing::field::Empty,
            similarity = tracing::field::Empty,
        ).entered();

        let dedup = auto_dedup_check(embedder, redb, &params.content, config.search.dedup_threshold)
            .context("auto-dedup check")?;

        if let Some(matched_id) = dedup.matched_id {
            info!(
                matched_id = %matched_id,
                similarity = dedup.similarity,
                "auto-dedup: superseding existing entry"
            );
            Span::current().record("matched", true);
            Span::current().record("similarity", dedup.similarity as f64);
            dedup_similarity = Some(dedup.similarity);
            supersedes = vec![matched_id];
            action = "superseded".to_string();
        } else {
            Span::current().record("matched", false);
            Span::current().record("similarity", 0.0f64);
            action = "created".to_string();
        }
        drop(_dedup_span);
    } else if !supersedes.is_empty() {
        action = "superseded".to_string();
    } else {
        action = "created".to_string();
    }

    // Step 4: Validate supersedes references.
    let warning = validate_supersedes(redb, &supersedes)?;
    if let Some(ref w) = warning {
        warn!("{}", w);
    }

    // Step 5: Create entry and write atomically.
    let entry = new_entry(
        params.content,
        params.kind,
        params.tags,
        supersedes.clone(),
    );
    let entry_id = entry.meta.id.clone();

    write_entry_atomic(&entries_dir, &entry)
        .with_context(|| format!("writing entry {}", entry_id))?;

    info!(id = %entry_id, action = %action, "entry written to disk");

    // Step 6: Update indexes.
    for sup_id in &supersedes {
        redb.set_superseded(sup_id, true)
            .with_context(|| format!("marking {} as superseded", sup_id))?;
    }
    redb.set_superseded(&entry_id, false)
        .with_context(|| format!("marking {} as current", entry_id))?;

    {
        let mut sup_writer = tantivy.writer().context("creating tantivy writer for supersession cleanup")?;
        for sup_id in &supersedes {
            tantivy.delete_by_entry_id(&sup_writer, sup_id);
        }
        sup_writer.commit().context("committing supersession deletes")?;
        tantivy
            .reload_reader()
            .context("reloading tantivy reader after supersession deletes")?;
    }

    {
        let _span = info_span!("corvia.write.index", chunk_count = tracing::field::Empty).entered();

        let chunks = chunk_entry(
            &entry,
            config.chunking.max_tokens,
            config.chunking.overlap_tokens,
            config.chunking.min_tokens,
        );
        Span::current().record("chunk_count", chunks.len());

        let mut writer = tantivy.writer().context("creating tantivy writer")?;

        for chunk in &chunks {
            let chunk_id = format!("{}:{}", entry_id, chunk.chunk_index);
            if chunk.text.is_empty() {
                continue;
            }
            let vector = embedder
                .embed(&chunk.text)
                .with_context(|| format!("embedding chunk {}", chunk_id))?;
            redb.put_vector(&chunk_id, &entry_id, &vector)
                .with_context(|| format!("storing vector for {}", chunk_id))?;
            redb.put_chunk_kind(&chunk_id, &chunk.kind.to_string())
                .with_context(|| format!("storing kind for {}", chunk_id))?;
            tantivy
                .add_doc(
                    &writer,
                    &chunk_id,
                    &entry_id,
                    &chunk.text,
                    entry.meta.kind,
                    false,
                )
                .with_context(|| format!("adding tantivy doc for {}", chunk_id))?;
        }

        writer.commit().context("committing tantivy writer")?;
        tantivy
            .reload_reader()
            .context("reloading tantivy reader after write")?;
    }

    // Step 7: Update entry count.
    let actual_count = crate::entry::scan_entries(&entries_dir)
        .context("scanning entries for count update")?
        .len();
    redb.set_meta("entry_count", &actual_count.to_string())
        .context("updating entry_count metadata")?;

    Span::current().record("action", action.as_str());
    Span::current().record("superseded_count", supersedes.len());

    info!(
        id = %entry_id,
        action = %action,
        superseded_count = supersedes.len(),
        "write pipeline complete"
    );

    Ok(WriteResponse {
        id: entry_id,
        action,
        superseded: supersedes,
        similarity: dedup_similarity,
        warning,
    })
}
```

- [ ] **Step 4: Replace `write()` with thin wrapper**

Replace the existing `write()` function (starting at the `#[tracing::instrument(name = "corvia.write"...` line) with this wrapper:

```rust
/// Write a new knowledge entry with auto-dedup detection.
///
/// Opens index handles internally. For callers that hold persistent handles,
/// use [`write_with_handles`] directly.
pub fn write(
    config: &Config,
    base_dir: &Path,
    embedder: &Embedder,
    params: WriteParams,
) -> Result<WriteResponse> {
    let entries_dir = base_dir.join(config.entries_dir());
    let index_dir = base_dir.join(config.index_dir());
    std::fs::create_dir_all(&entries_dir)
        .with_context(|| format!("creating entries dir: {}", entries_dir.display()))?;
    std::fs::create_dir_all(&index_dir)
        .with_context(|| format!("creating index dir: {}", index_dir.display()))?;

    let redb = RedbIndex::open(&base_dir.join(config.redb_path())).context("opening redb index")?;
    let tantivy = TantivyIndex::open(&base_dir.join(config.tantivy_dir())).context("opening tantivy index")?;
    write_with_handles(config, base_dir, embedder, params, &redb, &tantivy)
}
```

- [ ] **Step 5: Run all tests**

```bash
cargo test -p corvia-core 2>&1 | tail -20
```

Expected: all tests pass including `write_with_handles_signature_exists`.

- [ ] **Step 6: Commit**

```bash
git add crates/corvia-core/src/search.rs crates/corvia-core/src/write.rs
git commit -m "feat(core): add write_with_handles() for persistent index handle reuse"
```

---

### Task 4: Add HTTP serve infrastructure to `mcp.rs`

**Files:**
- Modify: `repos/corvia/crates/corvia-cli/src/mcp.rs`

This is the largest change. We add:
1. New imports (axum)
2. `IndexHandles` struct
3. `ServeState` struct
4. `mcp_post_handler()` axum handler
5. Helper functions: `handle_initialize_http()`, `handle_tools_list_http()`, `handle_tools_call_http()`, `handle_status_with_handles()`
6. `serve_http()` public entry point
7. Unit tests for the pure helpers

- [ ] **Step 1: Write failing unit tests first**

Add a new test module at the very end of `crates/corvia-cli/src/mcp.rs` (after the existing `run_test` function):

```rust
#[cfg(test)]
mod http_tests {
    use super::*;

    #[test]
    fn initialize_response_has_required_fields() {
        let resp = handle_initialize_http();
        assert!(resp.get("protocolVersion").is_some(), "missing protocolVersion");
        assert!(resp.get("capabilities").is_some(), "missing capabilities");
        assert!(resp.get("serverInfo").is_some(), "missing serverInfo");
        let caps = resp["capabilities"].as_object().unwrap();
        assert!(caps.contains_key("tools"), "capabilities missing tools");
    }

    #[test]
    fn tools_list_response_has_four_tools() {
        let resp = handle_tools_list_http();
        let tools = resp["tools"].as_array().expect("tools should be an array");
        assert_eq!(tools.len(), 4, "expected 4 tools");
        let names: Vec<&str> = tools
            .iter()
            .filter_map(|t| t.get("name").and_then(|n| n.as_str()))
            .collect();
        assert!(names.contains(&"corvia_search"));
        assert!(names.contains(&"corvia_write"));
        assert!(names.contains(&"corvia_status"));
        assert!(names.contains(&"corvia_traces"));
    }

    #[test]
    fn notification_has_no_id_field() {
        // Notifications: the client sends messages without an "id".
        // We verify our parsing logic correctly identifies them.
        let msg = serde_json::json!({
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
            "params": {}
        });
        assert!(msg.get("id").is_none(), "notifications must not have id");
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cargo test -p corvia -- http_tests 2>&1 | tail -15
```

Expected: compile error — `handle_initialize_http` not found.

- [ ] **Step 3: Add imports at the top of `mcp.rs`**

Add the following to the existing `use` block at the top of `crates/corvia-cli/src/mcp.rs` (after the existing imports, before the parameter structs):

```rust
use axum::{
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::post,
    Json, Router,
};
use tokio::sync::Mutex as TokioMutex;
```

- [ ] **Step 4: Add `IndexHandles` and `ServeState` structs**

Add after the existing `CorviaServer` struct definition (after line ~98):

```rust
// ---------------------------------------------------------------------------
// HTTP server state (for `corvia serve`)
// ---------------------------------------------------------------------------

/// Persistent index handles held open for the lifetime of the HTTP server.
///
/// `write_lock` serializes write operations (one write at a time); reads are concurrent.
struct IndexHandles {
    redb: RedbIndex,
    tantivy: TantivyIndex,
    write_lock: TokioMutex<()>,
}

/// Axum state shared across all HTTP MCP handler calls.
#[derive(Clone)]
struct ServeState {
    config: Arc<Config>,
    embedder: Arc<Embedder>,
    base_dir: std::path::PathBuf,
    handles: Arc<IndexHandles>,
}
```

- [ ] **Step 5: Add `handle_initialize_http()` and `handle_tools_list_http()`**

Add after the `ServeState` struct:

```rust
// ---------------------------------------------------------------------------
// HTTP MCP helper handlers
// ---------------------------------------------------------------------------

/// MCP `initialize` response — server capabilities handshake.
fn handle_initialize_http() -> serde_json::Value {
    serde_json::json!({
        "protocolVersion": "2024-11-05",
        "capabilities": {
            "tools": {}
        },
        "serverInfo": {
            "name": "corvia",
            "version": env!("CARGO_PKG_VERSION"),
        }
    })
}

/// MCP `tools/list` response — the four corvia tools.
fn handle_tools_list_http() -> serde_json::Value {
    let tools = vec![search_tool(), write_tool(), status_tool(), traces_tool()];
    serde_json::json!({ "tools": tools })
}
```

- [ ] **Step 6: Add `handle_status_with_handles()`**

Add after `handle_tools_list_http()`:

```rust
/// Status handler using pre-opened index handles.
fn handle_status_with_handles(
    config: &Config,
    base_dir: &std::path::Path,
    redb: &RedbIndex,
    tantivy: &TantivyIndex,
) -> Result<serde_json::Value> {
    let storage_path = base_dir.join(&config.data_dir);

    let entry_count = redb.entry_count().unwrap_or(0);
    let superseded_count = redb
        .superseded_ids()
        .map(|ids| ids.len() as u64)
        .unwrap_or(0);
    let vector_count = redb.vector_count().unwrap_or(0);
    let last_ingest = redb.get_meta("last_ingest").ok().flatten();

    let indexed_count_str = redb.get_meta("entry_count").ok().flatten();
    let indexed_count: u64 = indexed_count_str
        .as_deref()
        .and_then(|s| s.parse().ok())
        .unwrap_or(0);
    let entries_dir = base_dir.join(config.entries_dir());
    let actual_count = corvia_core::entry::scan_entries(&entries_dir)
        .map(|v| v.len() as u64)
        .unwrap_or(0);
    let stale = actual_count != indexed_count;

    let bm25_docs = tantivy.doc_count();

    let trace_path = base_dir.join(&config.data_dir).join("traces.jsonl");
    let parsed_traces = corvia_core::trace::read_recent_traces(&trace_path, 10);
    let recent_traces: Vec<corvia_core::types::TraceEntry> = parsed_traces
        .into_iter()
        .map(|t| corvia_core::types::TraceEntry {
            name: t.name,
            elapsed_ms: t.elapsed_ms,
            timestamp_ns: t.timestamp_ns,
            attributes: t.attributes,
        })
        .collect();

    let response = corvia_core::types::StatusResponse {
        entry_count,
        superseded_count,
        index_health: corvia_core::types::IndexHealth {
            bm25_docs,
            vector_count,
            last_ingest,
            stale,
        },
        storage_path: storage_path.display().to_string(),
        recent_traces,
    };

    Ok(serde_json::to_value(&response)?)
}
```

- [ ] **Step 7: Add `handle_tools_call_http()`**

Add after `handle_status_with_handles()`:

```rust
/// Route a `tools/call` request to the appropriate handler.
///
/// Returns `Ok(content_value)` on success or `Err(jsonrpc_error_object)` on failure.
async fn handle_tools_call_http(
    state: &ServeState,
    params: serde_json::Value,
) -> Result<serde_json::Value, serde_json::Value> {
    let name = params
        .get("name")
        .and_then(|n| n.as_str())
        .ok_or_else(|| {
            serde_json::json!({ "code": -32602, "message": "Missing tool name in params" })
        })?;

    let args = params
        .get("arguments")
        .cloned()
        .unwrap_or(serde_json::Value::Object(Default::default()));

    let tool_result: Result<serde_json::Value> = match name {
        "corvia_search" => {
            let p: SearchToolParams = serde_json::from_value(args).map_err(|e| {
                anyhow::anyhow!("invalid search params: {e}")
            })?;
            let redb = &state.handles.redb;
            let tantivy = &state.handles.tantivy;
            corvia_core::search::search_with_handles(
                &state.config,
                &state.base_dir,
                &state.embedder,
                &SearchParams {
                    query: p.query,
                    limit: p.limit,
                    max_tokens: p.max_tokens,
                    min_score: p.min_score,
                    kind: match &p.kind {
                        Some(k) => Some(k.parse::<Kind>().map_err(|e| anyhow::anyhow!(e))?),
                        None => None,
                    },
                },
                redb,
                tantivy,
            )
            .map(|r| serde_json::to_value(&r).unwrap_or_default())
        }
        "corvia_write" => {
            let p: WriteToolParams = serde_json::from_value(args).map_err(|e| {
                anyhow::anyhow!("invalid write params: {e}")
            })?;
            let kind = p.kind.parse::<Kind>().map_err(|e| anyhow::anyhow!(e))?;
            let _lock = state.handles.write_lock.lock().await;
            let redb = &state.handles.redb;
            let tantivy = &state.handles.tantivy;
            corvia_core::write::write_with_handles(
                &state.config,
                &state.base_dir,
                &state.embedder,
                corvia_core::write::WriteParams {
                    content: p.content,
                    kind,
                    tags: p.tags,
                    supersedes: p.supersedes,
                },
                redb,
                tantivy,
            )
            .map(|r| serde_json::to_value(&r).unwrap_or_default())
        }
        "corvia_status" => {
            handle_status_with_handles(
                &state.config,
                &state.base_dir,
                &state.handles.redb,
                &state.handles.tantivy,
            )
        }
        "corvia_traces" => {
            let p: TracesToolParams = serde_json::from_value(args).unwrap_or(TracesToolParams {
                limit: 10,
                span_filter: None,
            });
            handle_traces(&state.config, &state.base_dir, p)
        }
        other => {
            return Err(serde_json::json!({
                "code": -32602,
                "message": format!("Unknown tool: {other}"),
            }));
        }
    };

    match tool_result {
        Ok(value) => Ok(serde_json::json!({
            "content": [{ "type": "text", "text": value.to_string() }]
        })),
        Err(e) => Ok(serde_json::json!({
            "content": [{ "type": "text", "text": format!("Error: {e:#}") }],
            "isError": true,
        })),
    }
}
```

- [ ] **Step 8: Add `mcp_post_handler()` axum handler**

Add after `handle_tools_call_http()`:

```rust
/// Axum handler for POST /mcp — MCP Streamable HTTP transport (2025-06-18 spec).
async fn mcp_post_handler(
    State(state): State<ServeState>,
    Json(req): Json<serde_json::Value>,
) -> Response {
    let id = req.get("id").cloned();
    let method = req.get("method").and_then(|m| m.as_str()).unwrap_or("");
    let params = req
        .get("params")
        .cloned()
        .unwrap_or(serde_json::Value::Object(Default::default()));

    // Notifications have no id and expect no response body.
    if id.is_none() && method.starts_with("notifications/") {
        return StatusCode::ACCEPTED.into_response();
    }

    let result = match method {
        "initialize" => Ok(handle_initialize_http()),
        "tools/list" | "tools/list\n" => Ok(handle_tools_list_http()),
        "tools/call" => handle_tools_call_http(&state, params).await,
        "ping" => Ok(serde_json::json!({})),
        _ => Err(serde_json::json!({
            "code": -32601,
            "message": format!("Method not found: {method}"),
        })),
    };

    match result {
        Ok(value) => Json(serde_json::json!({
            "jsonrpc": "2.0",
            "id": id,
            "result": value,
        }))
        .into_response(),
        Err(err_obj) => Json(serde_json::json!({
            "jsonrpc": "2.0",
            "id": id,
            "error": err_obj,
        }))
        .into_response(),
    }
}
```

- [ ] **Step 9: Add `serve_http()` public entry point**

Add after `mcp_post_handler()`, before the existing `run()` function:

```rust
// ---------------------------------------------------------------------------
// Public entry point for HTTP MCP server
// ---------------------------------------------------------------------------

/// Start the HTTP MCP server. Called from `main.rs` when `corvia serve` is invoked.
///
/// Opens RedbIndex and TantivyIndex once at startup and holds them open for the
/// lifetime of the process. Multiple concurrent clients can connect; reads are
/// fully concurrent, writes are serialized via a tokio Mutex.
pub async fn serve_http(base_dir_arg: Option<&std::path::Path>, host: &str, port: u16) -> Result<()> {
    let base_dir = corvia_core::discover::resolve_base_dir(base_dir_arg)?;
    let config = Config::load_discovered(&base_dir).context("loading config")?;

    // Ensure required directories exist (handles fresh installs before first ingest).
    let index_dir = base_dir.join(config.index_dir());
    let entries_dir = base_dir.join(config.entries_dir());
    std::fs::create_dir_all(&index_dir)
        .with_context(|| format!("creating index dir: {}", index_dir.display()))?;
    std::fs::create_dir_all(&entries_dir)
        .with_context(|| format!("creating entries dir: {}", entries_dir.display()))?;

    // Open index handles once.
    info!("opening index handles");
    let redb = RedbIndex::open(&base_dir.join(config.redb_path()))
        .context("opening redb index")?;
    let tantivy_index = TantivyIndex::open(&base_dir.join(config.tantivy_dir()))
        .context("opening tantivy index")?;

    // Create embedder once (model loading is expensive).
    info!("initializing embedder (this may download models on first run)");
    let cache_dir = config.embedding.model_path.clone();
    let embedder = Embedder::new(
        cache_dir.as_deref(),
        &config.embedding.model,
        &config.embedding.reranker_model,
    )
    .context("initializing embedder")?;
    info!("embedder ready");

    let handles = Arc::new(IndexHandles {
        redb,
        tantivy: tantivy_index,
        write_lock: TokioMutex::new(()),
    });

    let state = ServeState {
        config: Arc::new(config),
        embedder: Arc::new(embedder),
        base_dir,
        handles,
    };

    let app = Router::new()
        .route("/mcp", post(mcp_post_handler))
        .with_state(state);

    let addr = format!("{host}:{port}");
    let listener = tokio::net::TcpListener::bind(&addr)
        .await
        .with_context(|| format!("binding to {addr}"))?;

    info!("corvia HTTP MCP server listening on http://{addr}/mcp");

    axum::serve(listener, app)
        .await
        .context("HTTP server error")?;

    Ok(())
}
```

- [ ] **Step 10: Run the unit tests**

```bash
cargo test -p corvia -- http_tests 2>&1 | tail -20
```

Expected:
```
test http_tests::initialize_response_has_required_fields ... ok
test http_tests::tools_list_response_has_four_tools ... ok
test http_tests::notification_has_no_id_field ... ok
```

- [ ] **Step 11: Build the whole workspace to catch any type errors**

```bash
cargo build --workspace 2>&1 | tail -10
```

Expected: `Finished \`dev\` profile`

If there are errors about `WriteParams` visibility (it's used via `corvia_core::write::WriteParams`), check that `WriteParams` is `pub` in write.rs. It is — verify with:
```bash
grep "^pub struct WriteParams" crates/corvia-core/src/write.rs
```

- [ ] **Step 12: Commit**

```bash
git add crates/corvia-cli/src/mcp.rs
git commit -m "feat(cli): add HTTP MCP server — ServeState, serve_http(), axum handler"
```

---

### Task 5: Add `Serve` subcommand to `main.rs`

**Files:**
- Modify: `repos/corvia/crates/corvia-cli/src/main.rs`

- [ ] **Step 1: Add `Serve` variant to the `Command` enum**

In `crates/corvia-cli/src/main.rs`, find the `Command` enum (around line 35). Add the `Serve` variant after the `Mcp` variant:

```rust
    /// Start HTTP MCP server (multi-client, persistent index handles)
    Serve {
        /// HTTP port to listen on
        #[arg(long, default_value = "8020")]
        port: u16,
        /// Host address to bind to (localhost only by default)
        #[arg(long, default_value = "127.0.0.1")]
        host: String,
    },
```

The full relevant portion of the `Command` enum should now look like:

```rust
    /// Start stdio MCP server
    Mcp {
        /// Run self-test and exit (validates config, models, tools)
        #[arg(long)]
        test: bool,
    },
    /// Start HTTP MCP server (multi-client, persistent index handles)
    Serve {
        /// HTTP port to listen on
        #[arg(long, default_value = "8020")]
        port: u16,
        /// Host address to bind to (localhost only by default)
        #[arg(long, default_value = "127.0.0.1")]
        host: String,
    },
    /// Initialize corvia in the current directory
    Init {
```

- [ ] **Step 2: Add the `Serve` arm to the `match` in `main()`**

Find the `match cli.command` block in `main()` (around line 129). Add a `Command::Serve` arm after the `Command::Mcp` arm:

```rust
        Command::Serve { port, host } => {
            mcp::serve_http(cli.base_dir.as_deref(), &host, port).await
        }
```

The relevant portion of main() should now read:

```rust
        Command::Mcp { test } => {
            if test {
                mcp::run_test(cli.base_dir.as_deref()).await
            } else {
                mcp::run(cli.base_dir.as_deref()).await
            }
        }
        Command::Serve { port, host } => {
            mcp::serve_http(cli.base_dir.as_deref(), &host, port).await
        }
        Command::Init { yes, force, model_path, format } => {
```

- [ ] **Step 3: Build and verify CLI help**

```bash
cargo build --workspace 2>&1 | tail -5
```

Expected: `Finished \`dev\` profile`

```bash
./target/debug/corvia serve --help
```

Expected output:
```
Start HTTP MCP server (multi-client, persistent index handles)

Usage: corvia serve [OPTIONS]

Options:
      --port <PORT>  HTTP port to listen on [default: 8020]
      --host <HOST>  Host address to bind to [default: 127.0.0.1]
  -h, --help         Print help
```

- [ ] **Step 4: Verify stdio MCP still works (doesn't hang forever, just starts)**

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}' | timeout 5 ./target/debug/corvia mcp 2>/dev/null | head -1
```

Expected: a JSON-RPC response line starting with `{"jsonrpc":"2.0"` (the server responds then waits for more input; timeout 5s kills it cleanly).

- [ ] **Step 5: Run all tests**

```bash
cargo test --workspace 2>&1 | grep -E "test result:|FAILED" | head -20
```

Expected: all `test result: ok`

- [ ] **Step 6: Commit**

```bash
git add crates/corvia-cli/src/main.rs
git commit -m "feat(cli): add 'corvia serve' subcommand for HTTP MCP server"
```

---

### Task 6: Update `.mcp.json` to HTTP transport

**Files:**
- Modify: `/workspaces/corvia-workspace/.mcp.json`

- [ ] **Step 1: Replace `.mcp.json` content**

Replace the entire content of `/workspaces/corvia-workspace/.mcp.json` with:

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

- [ ] **Step 2: Commit (workspace repo, not corvia repo)**

```bash
cd /workspaces/corvia-workspace
git add .mcp.json
git commit -m "feat: update MCP config to HTTP transport (corvia serve)"
```

Then commit the corvia repo changes:

```bash
cd /workspaces/corvia-workspace/repos/corvia
git add -A
git status
```

Expected: no new untracked files (everything was committed task by task).

---

### Task 7: Final verification

- [ ] **Step 1: Run the full test suite**

```bash
cd /workspaces/corvia-workspace/repos/corvia
cargo test --workspace 2>&1 | grep -E "test result:|FAILED"
```

Expected: all `test result: ok`, no FAILED.

- [ ] **Step 2: Start `corvia serve` and verify it binds**

In one terminal (background):
```bash
cd /workspaces/corvia-workspace
./repos/corvia/target/debug/corvia serve --port 8020 &
SERVE_PID=$!
sleep 2
```

- [ ] **Step 3: Test `initialize` handshake**

```bash
curl -s -X POST http://127.0.0.1:8020/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}' | python3 -m json.tool
```

Expected: JSON with `protocolVersion`, `capabilities.tools`, `serverInfo.name = "corvia"`.

- [ ] **Step 4: Test `tools/list`**

```bash
curl -s -X POST http://127.0.0.1:8020/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | python3 -m json.tool
```

Expected: JSON with `result.tools` array containing 4 entries (corvia_search, corvia_write, corvia_status, corvia_traces).

- [ ] **Step 5: Test two concurrent search requests succeed**

```bash
curl -s -X POST http://127.0.0.1:8020/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"corvia_search","arguments":{"query":"test"}}}' &

curl -s -X POST http://127.0.0.1:8020/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"corvia_search","arguments":{"query":"architecture"}}}' &

wait
```

Expected: Both return `{"jsonrpc":"2.0","id":...,"result":{"content":[...]}}`. No flock errors.

- [ ] **Step 6: Test `corvia mcp` (stdio) still works**

```bash
echo '{"jsonrpc":"2.0","id":5,"method":"tools/list","params":{}}' | timeout 5 ./repos/corvia/target/debug/corvia mcp 2>/dev/null | head -1
```

Expected: a JSON-RPC response containing the tools list.

- [ ] **Step 7: Stop serve and clean up**

```bash
kill $SERVE_PID 2>/dev/null; true
```

- [ ] **Step 8: Final workspace commit if needed**

```bash
cd /workspaces/corvia-workspace
git status
```

If `.mcp.json` shows modified, commit it. Otherwise, all done.

---

## Self-Review

**Spec coverage:**
- [x] Persistent index handles → `IndexHandles` with `Arc` in `ServeState` (Task 4)
- [x] HTTP transport → axum POST `/mcp` (Task 4)
- [x] `corvia serve` CLI command → Task 5
- [x] `corvia mcp` stdio unchanged → `run()` in mcp.rs untouched
- [x] Same 4 tools → `handle_tools_call_http()` dispatches to all 4
- [x] Write serialization → `write_lock: TokioMutex<()>` in `IndexHandles`
- [x] localhost default → `default_value = "127.0.0.1"` in CLI args
- [x] `.mcp.json` updated → Task 6
- [x] Tests pass → verified in each task

**Placeholder scan:** No TBDs, no vague steps. All code is complete.

**Type consistency:**
- `search_with_handles` defined in Task 2, used in Task 4's `handle_tools_call_http` via `corvia_core::search::search_with_handles`
- `write_with_handles` defined in Task 3, used in Task 4 via `corvia_core::write::write_with_handles`
- `WriteParams` in Task 4 is `corvia_core::write::WriteParams` — public struct, correct path
- `IndexHandles.tantivy` named `tantivy` (not `tantivy_index`) — consistent with Task 4 Step 9 which opens as `tantivy_index` then stores as `tantivy: tantivy_index`
- `ServeState` in `handle_tools_call_http` takes `&ServeState` — matches Task 8's `State<ServeState>` extractor which derefs
