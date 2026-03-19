# Architecture Challenge — 2026-03-19

> Critical evaluation of every major architectural decision in corvia.
> For each: the original rationale, honest pros/cons, and whether to keep/change.
> Reviewed by: Senior SWE, Product Manager, QA personas.

---

## D1: All-Rust Backend (no Python in production)

**Original rationale**: Speed (4,700 QPS vs Python ~300 QPS), type safety, single-language portfolio story.

**Pros:**
- Exceptional performance: 35ms RAG pipeline latency, 22ms embedding via gRPC
- Memory safety without GC pauses — critical for long-running server
- Single binary deployment (no pip, no virtualenvs, no version conflicts)
- Tree-sitter has native Rust bindings — zero FFI overhead
- Cargo workspace gives unified build/test across all crates

**Cons:**
- Slower iteration speed vs Python for ML/eval experimentation
- Ecosystem gap: no equivalent to LangChain, RAGAS, DeepEval in Rust
- Steeper contributor barrier — Rust async is complex
- ONNX Runtime Rust bindings (`ort` crate) are less mature than Python bindings
- Fine-tuning (M5c) still requires Python — the "all Rust" claim has an asterisk

**Verdict: KEEP.** The performance and reliability benefits are real and measurable. The ecosystem gap is shrinking (ort, candle, burn). For evals, write eval harness in Rust with shell scripts for orchestration, not a Python framework.

---

## D2: LiteStore as Full Product (not just dev tier)

**Original rationale**: Docker requirement kills developer tool adoption. LiteStore should be the real product, not a demo.

**Pros:**
- Zero external dependencies — `cargo install corvia && corvia init`
- 8,769 entries with 11,756 graph edges works fine in production
- HNSW index loads from disk in 0.09s
- JSON files as source of truth = git-diffable, rebuildable
- Redb is ACID — no data loss on crash

**Cons:**
- HNSW scales to ~100K entries before performance degrades (can't serve large orgs)
- petgraph in-memory means graph must fit in RAM
- No concurrent multi-process access (Redb is single-writer)
- JSON files are slow to rebuild at scale (8K entries = ~5s, 100K = minutes)
- No built-in replication or HA

**Challenge: Is 100K entries enough?** For the stated audience (dev tool, single team), yes. A large monorepo might generate 50-80K chunks. For enterprise multi-team, no — but that's what PostgresStore is for.

**Verdict: KEEP.** The zero-Docker value prop is a genuine competitive advantage. The 100K ceiling is acceptable for the target audience. Document the scaling boundary clearly.

---

## D3: Git-Tracked JSON Files as Source of Truth

**Original rationale**: Auditability, diffability, rebuildability. The database is a cache.

**Pros:**
- `git blame` shows who wrote every knowledge entry
- `corvia rebuild` reconstructs all indexes from JSON alone
- Easy backup: just `git push`
- Human-readable — can inspect and edit entries manually
- Merge conflicts in git are visible

**Cons:**
- **Performance**: Reading 8,769 JSON files from disk on rebuild is slow
- **Disk usage**: JSON + embedding vectors = ~300MB for 8K entries (bloated for git)
- **Git history**: Embedding vectors in JSON create massive diffs (768 floats per entry)
- **Concurrency**: File-per-entry means lots of small files — bad for filesystem inode limits at scale
- **Redundancy**: Same data exists in JSON files AND Redb AND HNSW index — triple storage

**Challenge: Should embeddings be stored in JSON?** The embedding vectors dominate file size and create terrible git diffs. Storing content + metadata in JSON but embeddings only in Redb/HNSW would reduce disk usage by ~80% and make git diffs actually readable.

**Verdict: CHANGE (minor).** Keep JSON as source of truth for content/metadata, but consider excluding embedding vectors from JSON files. They can always be re-computed from content. This would be a meaningful storage optimization.

---

## D4: LLM-Assisted Merge Over Last-Write-Wins

**Original rationale**: Knowledge conflicts are semantic, not textual. An LLM can reason about accuracy.

**Pros:**
- Semantically aware: understands that two descriptions of "how auth works" may conflict
- Produces merged output that combines insights from both entries
- Preserves knowledge that last-write-wins would silently destroy

**Cons:**
- **Latency**: LLM merge adds seconds per conflict (vs microseconds for last-write-wins)
- **Cost**: Every conflict requires an LLM call (GPU/API cost)
- **Reliability**: LLM can hallucinate during merge — may introduce incorrect content
- **Determinism**: Same conflict can produce different merges on different runs
- **Complexity**: Merge queue, retry logic, exponential backoff — all for a feature that triggers rarely

**Challenge: How often do conflicts actually occur?** In practice, with a single developer (the current user), conflicts are extremely rare. The merge worker is over-engineered for the current use case.

**Verdict: KEEP but SIMPLIFY.** The architecture is sound for the multi-agent future. But for now, the merge worker rarely fires. Consider adding metrics to track actual conflict rate before optimizing further.

---

## D5: petgraph In-Memory Graph + Redb Persistence

**Original rationale**: LiteStore needs traversal without external graph DB.

**Pros:**
- Full graph algorithms (BFS, DFS, shortest path, cycle detection) with no external service
- Fast: in-memory graph operations are sub-millisecond
- Redb persistence means graph survives restarts
- Graph rebuild from Redb on startup takes <0.1s

**Cons:**
- **Memory**: Graph must fit in RAM (11,756 edges ≈ ~1MB, but grows linearly)
- **No distributed graph**: Can't shard across nodes
- **Duplicate state**: Edges in both petgraph (in-memory) and Redb (on-disk)
- **No graph query language**: No Cypher, SPARQL, or Gremlin — just Rust API

**Challenge: Is the graph actually useful for retrieval?** The trace data shows graph expansion adds only ~1ms but the quality improvement hasn't been measured with recall benchmarks.

**Verdict: KEEP but MEASURE.** The graph is architecturally sound. But we need M6 eval data to prove it improves retrieval quality. If graph expansion doesn't meaningfully improve recall@k, it's complexity without value.

---

## D6: Separate Inference Server (corvia-inference, gRPC)

**Original rationale**: Decouple embedding from the main server. GPU resource isolation.

**Pros:**
- GPU memory isolated from server process — no OOM killing the API
- Can run on a different machine (edge compute, GPU server)
- gRPC is efficient for batch operations
- Supports multiple backends (CUDA, OpenVINO, CPU) independently

**Cons:**
- **Operational complexity**: Two processes to manage instead of one
- **Latency overhead**: gRPC call adds ~2-5ms per embedding (network + serialization)
- **Single point of failure**: If inference server dies, all search/write operations fail
- **Deployment friction**: Users must run both `corvia serve` and `corvia-inference`
- **Dev experience**: `corvia-dev` orchestrates both, but adds complexity

**Challenge: For local dev, is the separation worth it?** The 2-5ms overhead is significant when embedding latency is only 22ms. That's a 10-20% tax for process isolation.

**Verdict: KEEP for now.** The GPU isolation benefit is real (server doesn't crash when inference OOMs). But consider an in-process embedding mode for single-user local dev where gRPC overhead matters.

---

## D7: MCP as Primary Integration Protocol

**Original rationale**: Universal agent integration surface. Any MCP client can connect.

**Pros:**
- Adopted by Claude Code, Cursor, Windsurf, GitHub Copilot, Codex
- JSON-RPC 2.0 is simple, well-understood, language-agnostic
- `_meta` extension provides agent identity without spec changes
- Three-tier safety model prevents accidental data loss

**Cons:**
- **Performance**: JSON serialization overhead for every tool call
- **Streaming**: MCP doesn't natively support streaming results
- **Session management**: MCP sessions are stateless — corvia must manage session state server-side
- **No push notifications**: Server can't proactively notify clients (e.g., "new findings available")
- **Spec volatility**: MCP is evolving rapidly — breaking changes possible

**Challenge: Should corvia also offer a native Rust SDK?** For performance-critical integrations (e.g., embedding pipeline, CI/CD), a native Rust crate API would be much faster than MCP/JSON-RPC.

**Verdict: KEEP as primary, ADD native crate API.** MCP for universal access (any AI tool), Rust crate for performance-critical integrations. This is the Grafana model (HTTP API + native Go SDK).

---

## D8: Bi-Temporal Knowledge Model

**Original rationale**: Knowledge has two time axes — when it was recorded and when it was true.

**Pros:**
- Can answer "what did we know about auth 3 months ago?"
- Supersession chains track knowledge evolution
- `valid_from/valid_to` enable snapshot queries at any point in time

**Cons:**
- **Complexity**: Bi-temporal queries are hard to reason about
- **Storage cost**: Never-deleted entries (only superseded) means unbounded growth
- **Query performance**: Range scans over compound temporal keys get slower with history depth
- **User confusion**: Most users don't think in terms of "valid time" vs "recorded time"

**Challenge: Is anyone actually using temporal queries?** The dashboard has a history explorer and the API has temporal endpoints, but there's no telemetry on how often they're called.

**Verdict: KEEP but TRACK USAGE.** The model is architecturally clean and doesn't add runtime cost for non-temporal queries. Add metrics to measure actual temporal query usage before investing more in temporal features.

---

## D9: Dashboard as Standalone Vite/React App

**Original rationale**: M5 VS Code extension was the original plan; standalone dashboard emerged as a more universal alternative.

**Pros:**
- Works with any editor, not just VS Code
- Modern React + Vite = fast development iteration
- Rich visualization (force-directed graph, waterfall traces, sparklines)
- Hot module replacement for rapid UI development

**Cons:**
- **JavaScript dependency**: Adds Node.js runtime to a Rust project
- **Two build systems**: Cargo for backend, npm for frontend
- **Bundle size**: node_modules adds ~200MB to devcontainer
- **Security surface**: npm packages are a supply chain risk
- **Deployment**: Must serve both Rust server and Vite dev server (or build to static)

**Challenge: Could the dashboard be a Rust-native TUI or WASM app?** A TUI via `ratatui` would eliminate the Node dependency entirely. WASM + Leptos/Dioxus could serve the dashboard from the Rust server.

**Verdict: KEEP (for now).** The React dashboard delivers genuine value and was shipped quickly. But for M7 (OSS launch), consider building static assets into the corvia binary so `corvia serve` also serves the dashboard — no separate Node process needed.

---

## D10: AGPL-3.0 License

**Original rationale**: SaaS protection — prevents cloud providers from offering corvia-as-a-service.

**Pros:**
- Strong copyleft: any SaaS offering must open-source their modifications
- Proven model: Grafana, MinIO, MongoDB use similar strategies
- Dual-licensing path preserves commercial option

**Cons:**
- **Adoption friction**: Some companies ban AGPL in their dependency trees
- **Contributor friction**: AGPL requires CLA for dual-licensing
- **Perception**: Some developers see AGPL as "not truly open source"
- **Enforcement**: AGPL compliance for SaaS is hard to verify

**Challenge: Does AGPL make sense for a dev tool?** Cloud providers are unlikely to offer a niche dev tool as a service. The AGPL mostly deters potential contributors.

**Verdict: RECONSIDER for M7.** For OSS launch, the license choice directly impacts adoption. Apache-2.0 or MIT would maximize adoption. AGPL makes sense if a commercial SaaS offering is planned; otherwise it's adoption friction without benefit. **Recommend: decide before M7 based on go-to-market strategy.**

---

## Summary: What to Change

| Decision | Verdict | Action |
|----------|---------|--------|
| All-Rust backend | KEEP | None |
| LiteStore as full product | KEEP | Document 100K scaling boundary |
| Git JSON source of truth | CHANGE (minor) | Consider excluding embeddings from JSON files |
| LLM-assisted merge | KEEP but simplify | Add conflict rate metrics |
| petgraph + Redb graph | KEEP but measure | M6 evals must prove graph improves recall |
| Separate inference server | KEEP | Consider in-process mode for local dev |
| MCP primary protocol | KEEP + ADD | Add native Rust crate API |
| Bi-temporal model | KEEP + TRACK | Add temporal query usage metrics |
| Standalone React dashboard | KEEP (for now) | Build static assets into binary for M7 |
| AGPL-3.0 license | RECONSIDER | Decide before M7 based on go-to-market |

---

*Reviewed by: Senior SWE (architecture sound, D3/D10 concerns valid), PM (adoption friction from AGPL is real, graph value unproven), QA (need metrics for D4/D5/D8 before claiming value)*
