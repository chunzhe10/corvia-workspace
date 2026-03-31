# corvia-workspace

> Multi-repo workspace for [corvia](repos/corvia) — organizational memory for AI agents.

This file follows the [AGENTS.md standard](https://agents.md/).

## Workspace Layout

```
corvia-workspace/
├── AGENTS.md                # Cross-platform AI agent instructions (this file)
├── CLAUDE.md                # Claude Code wrapper (imports AGENTS.md)
├── corvia.toml              # Workspace config (repos, embedding, server, docs)
├── .agents/                 # Agent-agnostic skills & reference docs
│   └── skills/              # Reusable patterns for any AI assistant
├── .mcp.json                # MCP server config (Claude Code, Codex, etc.)
├── repos/
│   └── corvia/              # Core: kernel, server, CLI, adapters (Rust, AGPL-3.0)
├── .corvia/                 # Local knowledge store (LiteStore)
└── docs/
    ├── decisions/           # Workspace-level architectural decisions
    ├── learnings/           # Captured knowledge and patterns
    ├── marketing/           # LinkedIn carousels, brand assets
    └── plans/               # Active implementation plans
```

## Quick Reference

```bash
corvia workspace status          # Check workspace + service health
corvia search "query"            # Search ingested knowledge
corvia workspace ingest          # Index all repos
corvia workspace ingest --fresh  # Re-index from scratch
corvia serve &                   # Start server (auto-started by devcontainer)
corvia workspace init-hooks      # Generate doc-placement hooks from config
```

## Service Ports

| Port | Service | Description |
|------|---------|-------------|
| 8020 | API server + Dashboard | REST + MCP protocol + embedded dashboard |
| 8021 | Vite dev server (dev only) | Dashboard hot-reload for frontend development |
| 8030 | Inference | gRPC embedding + chat (ONNX Runtime) |

## MCP Server (Dogfooding)

This workspace uses corvia's own MCP server at `http://localhost:8020/mcp`.
Any MCP-compatible AI tool can connect to it. The server is started automatically
by the devcontainer's `post-start.sh`.

Available MCP tools (use `scope_id: "corvia"` for all calls):
- `corvia_search` — semantic search across ingested knowledge
- `corvia_write` — write knowledge entries (requires agent identity)
- `corvia_history` — entry supersession history
- `corvia_graph` — graph edges for an entry
- `corvia_reason` — run health checks on a scope
- `corvia_agent_status` — agent contribution summary
- `corvia_context` — retrieve assembled context (RAG retrieval only)
- `corvia_ask` — full RAG: question → AI-generated answer from knowledge
- `corvia_system_status` — system status (entry counts, agents, sessions, queue)
- `corvia_config_get` — read config section as JSON
- `corvia_config_set` — update hot-reloadable config value (requires confirmation)
- `corvia_adapters_list` — discovered adapter binaries
- `corvia_agents_list` — all registered agents
- `corvia_gc_run` — trigger garbage collection (requires confirmation)
- `corvia_rebuild_index` — rebuild HNSW vector index (requires confirmation)
- `corvia_agent_suspend` — suspend an agent (requires confirmation)
- `corvia_merge_retry` — retry failed merge entries (requires confirmation)
- `corvia_merge_queue` — inspect merge queue status

**IMPORTANT:** The `scope_id` for this workspace is `"corvia"` (defined in `corvia.toml`).
Do NOT use `"corvia-workspace"`, `"corvia-demo"`, or any other variant.

## Hybrid Tool Usage (corvia MCP + native tools)

**IMPORTANT: Always call corvia MCP tools FIRST before using native tools for any
development task or question.** corvia is the project's knowledge base — skipping it
means you risk re-discovering decisions that were already made or contradicting
established patterns. This applies to ALL agents (Claude Code, Codex, etc.).

### When to use corvia MCP tools (ALWAYS do this first)

- **Starting ANY task**: Call `corvia_search` or `corvia_ask` first to find prior decisions,
  design context, or patterns relevant to the work. **This is mandatory, not optional.**
- **Answering ANY question about the project**: Call `corvia_ask` before searching code.
- **Understanding "why"**: Use `corvia_ask` for questions about architecture, rationale,
  or past discussions (e.g., "why does LiteStore use JSON files?").
- **Exploring relationships**: Use `corvia_graph` to understand how concepts, components,
  or entries relate to each other.
- **Checking history**: Use `corvia_history` to see how a piece of knowledge evolved.
- **Recording decisions**: Use `corvia_write` to persist design decisions, architectural
  context, or implementation notes that future sessions should know.
- **Health checks**: Use `corvia_reason` to validate knowledge consistency in a scope.

### When to use native tools

- **Reading/editing specific files** — corvia doesn't replace file access.
- **Searching for code patterns** — precise text/regex matching in source code.
- **Running commands** — builds, tests, git, CLI tools.
- **File discovery** — finding files by name or extension.

### Hybrid patterns

| Task | corvia first | Then native tools |
|------|-------------|-------------------|
| Start a feature | `corvia_search` for prior art/decisions | Read relevant files, implement |
| Debug an issue | `corvia_ask` "how does X work?" | Search code, read files, fix |
| Explore unfamiliar area | `corvia_search` for high-level context | Search/read for code details |
| Make a design decision | `corvia_ask` for existing patterns | Write design doc, `corvia_write` to record |
| Review a PR or change | `corvia_context` for relevant knowledge | Read changed files, search for impact |

### Rule of thumb

> **corvia = project knowledge & context. Native tools = source code & execution.**
> **Always check corvia first** — it's fast and prevents re-discovering things that
> were already decided. Do NOT jump straight to file reads or code search without
> checking corvia for relevant context first.

## Agentic Retrieval Protocol

These rules govern how agents interact with corvia's MCP tools for maximum effectiveness.
The server handles complex logic (quality assessment, deduplication). Agents follow
simple unconditional rules.

1. **Check quality signals after search.** `corvia_search` responses include a
   `quality_signal` object with `confidence` (high/medium/low) and `suggestion`.
   If confidence is `low`, follow the `suggestion` field and retry once (max 1 retry).

2. **Inject context into subagents.** Before spawning subagents for non-trivial work,
   call `corvia_context` with `max_tokens` (recommended: 2000-3000) and `format: "compact"`.
   Include the returned context in the subagent prompt so it has organizational knowledge.

3. **Write discipline.** After discovering non-obvious insights, call `corvia_write`
   immediately. The server handles deduplication automatically. If a near-duplicate is
   detected, the server returns a message instead of writing. Use `force_write: true`
   to bypass if the content is intentionally similar but distinct.

4. **Use `min_score` when precision matters.** Pass `min_score` to `corvia_search`
   to filter out low-relevance results at the server level.

## Auto-Save Research Findings

When you discover something non-obvious during a task — a workaround, an architectural
insight, a gotcha, or a decision rationale — **proactively call `corvia_write` to
persist it** without waiting for the user to ask. This includes:

- **Debugging insights**: Root cause of a bug, workaround, or environment-specific behavior
- **Architectural patterns**: How components interact, why a design was chosen
- **Configuration gotchas**: Non-obvious settings, version incompatibilities, ordering constraints
- **Performance observations**: Benchmark results, resource consumption patterns

Use `content_role: "learning"` and `source_origin: "workspace"` for workspace-level
findings, or `source_origin: "repo:corvia"` for product-specific knowledge.

**Do NOT auto-save**: trivial facts easily found in code comments, temporary debugging
state, or user-specific preferences. The bar is: "Would a future agent session benefit
from knowing this?"

## Superpowers Plugin (Required)

This workspace uses the [obra/superpowers](https://github.com/obra/superpowers) plugin
for structured development workflows. For non-trivial work (3+ files, new architecture,
or when the user explicitly asks), use these skills instead of ad-hoc alternatives.
For quick questions, small renames, or single-file fixes, use your judgment.

- **Dev Loop** (preferred): Use `/dev-loop <issue-number>` for the full autonomous
  development lifecycle: issue intake → brainstorming → planning → implementation →
  5-persona review → E2E testing → PR → merge. See `.agents/skills/dev-loop/SKILL.md`.
- **Brainstorming**: When asked to brainstorm, design, or plan a feature, use the
  superpowers `brainstorming` skill. This enforces the structured flow: explore context
  → clarifying questions → 2-3 approaches → design → spec doc → review loop.
- **Code review**: Use `requesting-code-review` / `receiving-code-review` skills
  for non-trivial changes before committing.
- **Plan execution**: Use `executing-plans` skill when implementing from a spec.
- **Debugging**: Use `systematic-debugging` skill for non-obvious bugs.

Skills are in the plugin's `skills/` subdirectory. When in doubt, read the relevant
`SKILL.md` before proceeding. The `dev-loop` skill orchestrates all of the above
into a single autonomous pipeline.

## AI Development Learnings

This workspace incorporates proven patterns from community best practices.
See [.agents/skills/ai-assisted-development.md](.agents/skills/ai-assisted-development.md)
for the full reference.

Key principles applied here:
- **Context engineering > prompt engineering** — AGENTS.md is essential infrastructure
- **Verify explicitly** — give pass/fail criteria, run tests before claiming success
- **Guard context** — delegate research to subagents, compact proactively, fresh sessions per task
- **Record decisions** — use `corvia_write` to persist learnings (dogfood the product)

## Self-Running Agent BKMs

Best Known Methods for autonomous, long-running Claude Code sessions. Adapted from
[Anthropic engineering](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents),
[self-improving agents](https://addyosmani.com/blog/self-improving-agents/), and
[obra/superpowers](https://github.com/obra/superpowers).

### Session Continuity & Progress Tracking

- **Progress file**: Maintain a session log (`docs/session-logs/<date>-<task>.md`)
  with hard fails, decisions, and checkpoints. Enables context recovery across sessions.
- **Git-based state**: Commit after every logical unit of work with descriptive messages.
  Git history becomes the primary memory mechanism between sessions.
- **JSON for critical state**: Use JSON over markdown for state files that agents
  modify — models are less likely to corrupt structured data.
- **Single-feature focus**: Work on one feature/fix at a time. Complete it fully
  (implement → test → verify → commit) before moving to the next.

### Autonomous Execution Loop

```
1. Health check (build + tests pass?)
2. Read session log / progress file
3. corvia_search for relevant context
4. Pick next task (smallest unblocked item)
5. Implement with verification criteria defined upfront
6. Run tests + manual verification
7. Multi-persona review (SWE / PM / QA)
8. Commit + update session log
9. Record findings to corvia (corvia_write)
10. Repeat or hand off
```

### Multi-Persona Review Gate

Every non-trivial change is reviewed through **five** independent lenses before commit.
Three are standard; two are dynamic based on the task (see `dev-loop` skill for selection table):

**Standard (always present):**
- **Senior SWE**: Correctness, safety, idiomatic patterns, edge cases, performance
- **Product Manager**: Goal alignment, UX coherence, milestone advancement, scope
- **QA Engineer**: Test coverage, E2E verification, failure modes, regression risk

**Dynamic (task-dependent, select two):**
- Chosen based on issue labels and changed files (e.g., Security Engineer for auth work,
  Performance Engineer for optimization, UX Designer for dashboard changes)

Each reviewer MUST be a deep, independent subagent run — not a shallow one-liner.
Reviews producing less than 10 lines of substantive feedback are invalid.

### Error Recovery

- **Never retry blindly** — diagnose root cause first
- **Log every failure** in the session log with full context
- **Fix forward** — address the underlying issue, not just the symptom
- **Verify the fix** with a test that would have caught the original bug
- **Record in corvia** so future sessions don't hit the same issue

### Parallelization

- **Subagents for research** — delegate broad exploration to background agents
- **Worktrees for isolation** — use git worktrees for parallel implementation work
- **Max 3-4 concurrent** — quality over quantity
- **Sequential phases produce files** — Research → Plan → Implement → Review → Verify

### Context Guard

- Delegate research to subagents (separate context windows)
- Keep files modular (hundreds of lines, not thousands)
- Compact proactively at ~70% context usage
- Fresh sessions per unrelated task
- Include only task-relevant context, not entire codebase docs

### Safety Boundaries

- Work on feature branches, never master directly
- Auto-approve reads; confirm destructive writes
- Run tests before AND after changes
- Never force-push, never skip hooks
- Use Docker for isolation when testing risky operations

For the full autonomous protocol, see [CLAUDE-AUTONOMOUS.md](CLAUDE-AUTONOMOUS.md).

## Production Agent BKMs

Best Known Methods for building production-grade AI agents, adapted from
[agents-towards-production](https://github.com/NirDiamant/agents-towards-production).

### Architecture

- **Graph-based orchestration**: Use directed graph architectures with explicit state
  transitions for multi-step workflows. Avoid linear chains for anything non-trivial.
- **Layered separation of concerns**: Keep orchestration, memory, tools, security, and
  evaluation as distinct layers. Do not mix tool-calling logic with reasoning logic.
- **Protocol-first integration**: Adopt MCP for tool integration and A2A for multi-agent
  communication. Protocol-based design makes agents composable and replaceable.

### Memory Systems

- **Dual-memory architecture**: Short-term (session/conversation context) + long-term
  (persistent knowledge with semantic search — this is what corvia provides).
- **Self-improving memory**: Design memory that evolves through interaction — automatic
  insight extraction, conflict resolution, and knowledge consolidation across sessions.

### Security (Defense-in-Depth)

- **Three-layer guardrails**: Input validation (prompt injection prevention), behavioral
  constraints (during execution), and output filtering (before delivery to user).
- **Tool access control**: Restrict which tools an agent can invoke based on user context
  and permissions. Never give agents unrestricted access to external tools.
- **User isolation**: Prevent cross-user data leakage in multi-user deployments.

### Observability

- **Trace every decision point**: Capture the full reasoning chain — which tools were
  called, what the LLM decided, timing data for each step.
- **Instrument from day one**: Do not bolt on observability later. Traces are essential
  for debugging, performance analysis, and evaluation.
- **Monitor cost, latency, accuracy** continuously, not just during development.

### Evaluation & Testing

- **Domain-specific test suites**: Build evaluation sets tailored to your domain.
  Generic benchmarks are insufficient.
- **Multi-dimensional metrics**: Evaluate beyond accuracy — include cost per interaction,
  latency, safety compliance, and tool-use correctness.
- **Iterative improvement cycles**: Evaluation should produce actionable insights that
  feed back into agent refinement.

### Deployment Strategy

- **Containerize everything**: Docker for portability and environment consistency.
- **Start stateless, migrate to persistent**: Prototype without memory, then layer in
  persistence once the workflow is stable.
- **Production readiness progression**: Prototype → Functional (add memory, auth, tracing)
  → Production (guardrails, evaluation, observability) → Scaled (multi-agent, GPU, fine-tuning).

## Repo-Specific Instructions

For detailed build/test/architecture guidance, see:
- [repos/corvia/AGENTS.md](repos/corvia/AGENTS.md) — kernel, server, CLI, adapters

## Development

- **Language**: Rust workspace (cargo)
- **Storage**: LiteStore (default, zero-Docker) — data in `.corvia/`
- **Embedding**: corvia-inference server at `http://127.0.0.1:8030` (default: nomic-embed-text-v1.5 768d; also supports all-MiniLM-L6-v2 384d)
- **API server**: `http://127.0.0.1:8020` (REST + MCP)
- **Config**: `corvia.toml` at workspace root
