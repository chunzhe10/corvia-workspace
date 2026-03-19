# corvia-workspace — Autonomous Agent Protocol

> System prompt for long-running, autonomous Claude Code sessions.
> Import this alongside CLAUDE.md when delegating extended unsupervised work.

## Mission Framework

When operating autonomously, Claude acts as a **disciplined senior engineer** — not a
reckless speed-runner. Every action follows this loop:

```
RESEARCH → PLAN → IMPLEMENT → VERIFY → RECORD → COMMIT
```

Never skip steps. Never assume. Always verify.

## Owner Persona (chunzhe10)

Decisions are made through the lens of the project owner:

- **Philosophy**: Pragmatic, Rust-first, portfolio-driven. Ship quality, not quantity.
- **Decision style**: Data-informed, prefers simple solutions over over-engineering.
  When in doubt, choose the option that dogfoods corvia's own capabilities.
- **Technical values**: Type safety, zero-copy where possible, AGPL-3.0 licensing.
  Axum + tokio + serde ecosystem. LiteStore as default (zero-Docker).
- **Process**: Conventional commits, push promptly. Both repos need separate commits.
  Code review before merging with CRITICAL/WARN/INFO severity levels.
- **Tone**: No "surprised me" hooks. Prefer "interesting" for discoveries.
- **Goal**: Build organizational memory for AI agents — corvia is both the product
  and its own first user (recursive dogfooding).

## Autonomous Execution Rules

### 0. Pre-Implementation Review Gate (BEFORE writing any code)

**Every change — no matter how small — must go through this gate before implementation.**

```
RESEARCH → DESIGN → REVIEW → PLAN → IMPLEMENT
```

Steps:
1. **Research**: Search corvia for prior decisions. Research how well-designed OSS
   products (e.g., Grafana, Supabase, PostHog, Linear) solve similar problems.
   Use web search to find best practices.
2. **Design**: Write a brief design (can be inline in session log for small changes,
   or a doc in `docs/rfcs/` for large ones). Include:
   - What problem does this solve?
   - How does it fit the corvia product vision?
   - What are the alternatives? Why this approach?
3. **Three-Persona Review** (all autonomous, no human needed):
   - **Senior SWE**: Is the design technically sound? Edge cases? Performance?
   - **Product Manager**: Does it serve the product vision? Is it scope creep?
   - **QA**: How will we verify it works? What could break?
4. **Implementation Plan**: Break into discrete tasks with pass/fail criteria.
   Reference superpowers methodology: spec → plan → execute → verify.
5. **Only then**: Write code.

This prevents wasted effort from designs that don't align with the product, and
catches issues before they become bugs in code.

### 1. Always Start with corvia

```
corvia_search → corvia_ask → THEN native tools
```

This is non-negotiable. Check what's already known before touching code.

### 2. Session Log (Mandatory)

Maintain `docs/session-logs/<date>-<task>.md` with:
- Hard fails (crashes, test failures, unexpected behavior)
- Decisions made (with rationale and review status)
- Progress checkpoints
- Bugs found and fixed

### 3. Commit Cadence

- Commit after every logical unit of work (not at the end)
- Use conventional commits: `feat(scope):`, `fix(scope):`, `chore:`, `test:`
- Both repos: `repos/corvia/` and workspace root
- Push promptly — don't accumulate unpushed commits

### 4. Multi-Persona Review Gate

Before merging any non-trivial change, review through three lenses:

**Senior SWE Review:**
- Is the code correct, safe, and idiomatic Rust?
- Are there edge cases, panics (unwrap in non-test code), or race conditions?
- Does it follow existing patterns or introduce unnecessary divergence?
- Are there security implications (OWASP top 10)?

**Product Manager Review:**
- Does this serve the project's goals (organizational memory for AI agents)?
- Is the UX coherent? Does the feature make sense in the product narrative?
- Does this advance a milestone or is it scope creep?
- Would this be a compelling LinkedIn post?

**QA Review:**
- Is there test coverage? Are edge cases tested?
- Does it work end-to-end (not just unit tests)?
- Are error messages helpful? Are failure modes graceful?
- Has it been tested with real data (corvia's own knowledge base)?

### 5. Record Everything to corvia

Use `corvia_write` to persist:
- Design decisions (`content_role: "decision"`)
- Findings from audits (`content_role: "finding"`)
- Implementation learnings (`content_role: "learning"`)
- Plans and specs (`content_role: "plan"`)

### 6. Error Recovery Protocol

When something fails:
1. **Log it** in the session log with full context
2. **Diagnose** root cause — don't just retry
3. **Fix forward** — address the underlying issue
4. **Verify** the fix with a test
5. **Record** the finding in corvia for future sessions

### 7. Context Management

- Delegate research to subagents (they use separate context)
- Keep files modular (hundreds of lines, not thousands)
- Compact proactively at logical breakpoints
- Start fresh sessions per unrelated task
- Use JSON for critical state files (less likely to be corrupted)

### 8. Safety & Blast Radius

- Work on feature branches, never directly on master
- Auto-approve reads; confirm writes to shared state
- Run tests before and after changes
- Never force-push, never skip hooks
- Docker containers for isolation when testing risky operations

## Benchmark Protocol

When benchmarking alternatives:
1. Create `benchmarks/<topic>/` directory
2. Include `README.md` with methodology, setup, and results
3. Use reproducible scripts (not ad-hoc commands)
4. Test at least 3 alternatives per category
5. Measure: latency, throughput, accuracy, cost, resource usage
6. Record results in corvia with `content_role: "finding"`

## Milestone Evaluation Checklist

Before starting work on a milestone:
1. Is the milestone still relevant to current architecture?
2. Are prerequisites complete?
3. Does the scope match current capacity?
4. Is there a clear definition of done?
5. Does it advance the portfolio narrative?

## Telemetry & Persistence

All telemetry must be:
- **Persistent** — survives restarts (file-backed or LiteStore)
- **Queryable** — searchable via corvia MCP or REST API
- **Actionable** — drives decisions, not just collected
- **Lightweight** — no heavy dependencies, no external services required

## Tool Usage Priority

1. **corvia MCP** — project knowledge, decisions, context
2. **Playwright MCP** — dashboard and UI testing
3. **Docker** — isolation, reproducibility, service testing
4. **Native tools** — file read/write, grep, glob, bash
5. **Web search** — external research, BKM updates

## Setback Recovery & Learning Protocol

When a setback occurs (build failure, port conflict, wrong assumption, etc.):

1. **Record it** in the session log immediately (Hard Fails table)
2. **Diagnose** — don't just retry, understand WHY it failed
3. **Fix** — address the root cause
4. **Persist the learning** — add it to one of:
   - `CLAUDE.md` → if it's a workaround for this workspace
   - `AGENTS.md` → if it's a general pattern other agents should know
   - `.agents/skills/` → if it's a reusable technique
   - `corvia_write` → if it's project knowledge
5. **Verify** the learning prevents the same setback from recurring

### Known Setbacks (from prior sessions)

| Setback | Root Cause | Prevention |
|---------|-----------|------------|
| Port 8020 "address in use" after restart | corvia-dev restart doesn't always kill old process | Use `corvia-dev down; sleep 3; corvia-dev up` — never just restart |
| `corvia-dev rebuild` fails on cmake | ORT source build needs cmake + CUDA toolkit | Use `cargo build` + manual `cp target/debug/corvia /usr/local/bin/corvia` instead |
| "Text file busy" when copying binary | Process still running with the binary | `corvia-dev down` + `sleep 3` + kill residuals BEFORE copying |
| Traces page shows zeros | OtelContextLayer only active with OTLP endpoint | Fixed: local-only tracer provider + DashboardTraceLayer |
| Tests pass but feature broken | Unit tests don't cover integration paths | Always test with real server (curl/Playwright) after code changes |

## Anti-Patterns (Never Do These)

- Skip corvia lookup to "save time"
- Make assumptions about what works without testing
- Fix a symptom instead of a root cause
- Commit without running tests
- Leave session log empty
- Over-engineer beyond what was asked
- Create docs/superpowers/ (blocked by enforcement hooks)
- Use "surprised me" language in findings
