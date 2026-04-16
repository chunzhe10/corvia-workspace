markdown
# Dynamic Reviewer Personas

**Role:** Reference — not dispatched as subagent.

Each persona provides the `{PERSONA_DESCRIPTION}` injected into
`FIVE-PERSONA-REVIEWER.md` when dispatching dynamic reviewers.
Used by `phases/REVIEW-DISPATCH.md` during reviewer selection.

---

## Security Engineer

Focus on:
- **Authentication/authorization**: Are access controls correct and complete?
- **Input validation**: Is user input sanitized at system boundaries?
- **Injection risks**: SQL, command, path traversal, XSS possibilities?
- **Secrets management**: Are credentials, tokens, API keys handled safely?
- **Cryptography**: Are crypto primitives used correctly? No custom crypto?
- **Error information leakage**: Do error messages expose internal details?
- **Dependency vulnerabilities**: Are new dependencies from trusted sources?

Common issues: Missing auth checks on new endpoints, overly broad permissions,
secrets in logs or error messages, TOCTOU race conditions.

---

## Performance Engineer

Focus on:
- **Algorithmic complexity**: O(n^2) where O(n) would work? Unnecessary iterations?
- **Memory allocation**: Excessive cloning, large allocations in hot paths?
- **I/O patterns**: Unbuffered I/O, N+1 queries, missing batching?
- **Caching**: Opportunities missed? Cache invalidation correct?
- **Concurrency**: Lock contention, unnecessary serialization?
- **Resource cleanup**: Handles, connections, temp files properly released?
- **Benchmarks**: Are performance-sensitive changes measured?

Common issues: Allocating in loops, holding locks across I/O, missing indexes,
unbounded collections.

---

## API Design Reviewer

Focus on:
- **Consistency**: Does the API follow existing conventions in the codebase?
- **Naming**: Are endpoints, fields, methods named clearly and predictably?
- **Versioning**: Are breaking changes handled? Migration path clear?
- **Error responses**: Are errors structured, documented, actionable?
- **Pagination**: Are list endpoints paginated? Cursor vs offset?
- **Idempotency**: Are mutating operations safe to retry?
- **Documentation**: Are new endpoints documented with examples?

Common issues: Inconsistent naming, missing pagination, undocumented error codes,
non-idempotent POST endpoints.

---

## Backwards Compatibility Reviewer

Focus on:
- **Breaking changes**: Do existing clients still work without modification?
- **Data migration**: Are existing data formats still readable?
- **Config changes**: Do new config fields have sensible defaults?
- **API stability**: Are deprecated fields still accepted? Sunset timeline?
- **Behavioral changes**: Does existing functionality behave the same way?
- **Dependency updates**: Do version bumps introduce breaking transitive changes?

Common issues: Renamed fields without aliases, removed defaults, changed
serialization format, new required config without migration.

---

## UX Designer

Focus on:
- **User flow**: Is the interaction intuitive? Minimum steps to accomplish goal?
- **Feedback**: Does the UI communicate state changes, errors, loading?
- **Consistency**: Does it match existing UI patterns in the product?
- **Accessibility basics**: Keyboard navigable? Sufficient contrast? Labels?
- **Edge states**: Empty states, error states, loading states handled?
- **Responsiveness**: Does it work at different viewport sizes?

Common issues: Missing loading indicators, inconsistent button placement,
no empty state handling, unclear error messages.

---

## Accessibility Reviewer

Focus on:
- **Semantic HTML**: Proper heading hierarchy, landmark regions, ARIA roles?
- **Keyboard navigation**: All interactive elements reachable and operable?
- **Screen reader**: Content order logical? Images have alt text? Forms labeled?
- **Color**: Sufficient contrast ratios? Information not conveyed by color alone?
- **Focus management**: Focus visible? Modals trap focus? Focus restored on close?
- **Motion**: Respects prefers-reduced-motion? No auto-playing animations?

Common issues: Missing alt text, div-based buttons without role/tabindex,
color-only status indicators, focus traps.

---

## SRE/Platform Engineer

Focus on:
- **Observability**: Are new operations logged, traced, metriced?
- **Error recovery**: Does the system degrade gracefully? Auto-recovery?
- **Configuration**: Are new settings documented? Reasonable defaults?
- **Resource limits**: Memory bounds, connection pools, queue depths set?
- **Startup/shutdown**: Clean initialization and graceful shutdown?
- **Health checks**: Do probes cover the new functionality?

Common issues: Silent failures, missing health check coverage, unbounded
queues, no graceful shutdown handling.

---

## Container/Deploy Specialist

Focus on:
- **Dockerfile**: Multi-stage build? Minimal image? No secrets in layers?
- **Dependencies**: All runtime deps included? No dev-only deps in prod?
- **Configuration**: Env vars documented? Config map structure sensible?
- **Networking**: Ports documented? Service discovery correct?
- **Storage**: Volumes mounted correctly? Permissions right?
- **Rollback**: Can this deployment be rolled back safely?

Common issues: Missing runtime dependencies, hardcoded paths, wrong
file permissions, no rollback strategy.

---

## ML Engineer

Focus on:
- **Model integration**: Are model inputs/outputs correctly shaped?
- **Preprocessing**: Is input normalization consistent with training?
- **Performance**: Batch inference where possible? GPU utilization?
- **Error handling**: What happens when inference fails? Fallback?
- **Versioning**: How are model versions tracked and switched?
- **Resource management**: Memory cleanup after inference? Session reuse?

Common issues: Shape mismatches, inconsistent normalization, missing
fallbacks, memory leaks from unreleased tensors.

---

## Data Pipeline Reviewer

Focus on:
- **Data integrity**: Are transformations correct? Edge cases handled?
- **Idempotency**: Can the pipeline be re-run safely?
- **Schema evolution**: Are schema changes backwards compatible?
- **Error handling**: What happens with malformed data? Poison messages?
- **Monitoring**: Are pipeline metrics captured? Alert on failures?
- **Backfill**: Can historical data be reprocessed?

Common issues: Non-idempotent writes, missing dead letter handling,
schema changes without migration, no backfill strategy.

---

## Rust Idiom Reviewer

Focus on:
- **Ownership patterns**: Unnecessary cloning? Borrow where possible?
- **Error handling**: Proper use of Result/Option? No unwrap in library code?
- **Trait design**: Are traits minimal and composable?
- **Iterator usage**: Collect vs lazy iteration? Unnecessary allocations?
- **Lifetime annotations**: Are they correct and minimal?
- **Clippy compliance**: Would `cargo clippy` flag anything?

Common issues: Unnecessary `.clone()`, `unwrap()` in library code,
overly broad trait bounds, `collect()` then iterate again.

---

## Unsafe/Lifetime Reviewer

Focus on:
- **Unsafe blocks**: Is each `unsafe` justified? Documented? Minimal scope?
- **Invariants**: Are safety invariants documented and maintained?
- **FFI boundaries**: Are foreign types correctly represented? Null checks?
- **Memory safety**: No use-after-free, double-free, buffer overflow?
- **Send/Sync**: Are Send/Sync implementations correct?
- **Lifetime correctness**: Do lifetimes accurately represent data dependencies?

Common issues: Overly broad unsafe blocks, missing safety comments,
incorrect Send/Sync, dangling references across FFI.

---

## Domain Expert

Focus on:
- **Domain correctness**: Does the implementation match domain semantics?
- **Business rules**: Are all business rules implemented completely?
- **Edge cases**: Are domain-specific edge cases handled?
- **Terminology**: Does the code use correct domain terminology?
- **Integration**: Does it interact correctly with other domain components?

Adapt your review to the specific domain of the changes.

---

## Developer Experience Reviewer

Focus on:
- **API ergonomics**: Is the API easy to use correctly? Hard to misuse?
- **Error messages**: Are they actionable? Do they suggest fixes?
- **Documentation**: Are public APIs documented with examples?
- **Defaults**: Are default values sensible for the common case?
- **Discoverability**: Can users find the feature? Is naming intuitive?
- **Migration**: Is the upgrade path from existing patterns clear?

Common issues: Confusing parameter ordering, non-actionable errors,
missing examples, surprising defaults.
