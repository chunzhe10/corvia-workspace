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

## MCP Server (Dogfooding)

This workspace uses corvia's own MCP server via **HTTP** (`http://127.0.0.1:8020/mcp`).
It is configured in `.mcp.json` and auto-started by the devcontainer post-start sequence.

Available MCP tools:
- `corvia_search` — semantic search across ingested knowledge
- `corvia_write` — write a knowledge entry (auto-deduplicates: cosine similarity ≥ 0.85 triggers supersession)
- `corvia_status` — check system health and indexed entry counts
- `corvia_traces` — inspect recent operation traces

**Entry schema**: `id`, `created_at`, `kind`, `supersedes`, `tags` + markdown body.
**Entry storage**: flat `.md` files with TOML frontmatter in `.corvia/entries/`.
**Lifecycle**: supersession only — no GC, TTL, or decay.
**Write model**: each `corvia_write` is an individual operation (no batch writes).

## Hybrid Tool Usage (corvia MCP + native tools)

**IMPORTANT: Always call corvia MCP tools FIRST before using native tools for any
development task or question.** corvia is the project's knowledge base — skipping it
means you risk re-discovering decisions that were already made or contradicting
established patterns. This applies to ALL agents (Claude Code, Codex, etc.).

### Hybrid patterns

| Task | corvia first | Then native tools |
|------|-------------|-------------------|
| Start a feature | `corvia_search` for prior art/decisions | Read relevant files, implement |
| Debug an issue | `corvia_search` "how does X work?" | Search code, read files, fix |
| Explore unfamiliar area | `corvia_search` for high-level context | Search/read for code details |
| Make a design decision | `corvia_search` for existing patterns | Write design doc, `corvia_write` to record |
| Review a PR or change | `corvia_search` for relevant knowledge | Read changed files, search for impact |

## Agentic Retrieval Protocol

These rules govern how agents interact with corvia's MCP tools for maximum effectiveness.
The server handles complex logic (quality assessment, deduplication). Agents follow
simple unconditional rules.

1. **Check quality signals after search.** `corvia_search` responses include a
   `quality_signal` object with `confidence` (high/medium/low) and `suggestion`.
   If confidence is `low`, follow the `suggestion` field and retry once (max 1 retry).

2. **Write discipline.** After discovering non-obvious insights, call `corvia_write`
   immediately. Auto-dedup runs on every write: if cosine similarity to an existing entry
   is ≥ 0.85, the server automatically creates a supersession instead of a duplicate.

3. **Use `min_score` when precision matters.** Pass `min_score` to `corvia_search`
   to filter out low-relevance results at the server level.

## Auto-Save Research Findings

When you discover something non-obvious during a task — a workaround, an architectural
insight, a gotcha, or a decision rationale — **proactively call `corvia_write` to
persist it** without waiting for the user to ask. This includes:

- **Debugging insights**: Root cause of a bug, workaround, or environment-specific behavior
- **Architectural patterns**: How components interact, why a design was chosen
- **Configuration gotchas**: Non-obvious settings, version incompatibilities, ordering constraints
- **Performance observations**: Benchmark results, resource consumption patterns

Use `kind: "learning"` when writing insights. Entry fields are limited to `id`,
`created_at`, `kind`, `supersedes`, and `tags` — there is no session or source metadata.

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

For autonomous session patterns (execution loop, multi-persona review gate, error recovery, parallelization): see `.claude/CLAUDE-AUTONOMOUS.md`.

For production agent architecture patterns (graph orchestration, memory systems, security, observability, deployment): see `docs/learnings/production-agent-bkms.md`.

## Repo-Specific Instructions

For detailed build/test/architecture guidance, see:
- [repos/corvia/AGENTS.md](repos/corvia/AGENTS.md) — kernel, server, CLI, adapters

## Development

- **Language**: Rust workspace (cargo)
- **Storage**: LiteStore (default, zero-Docker) — flat `.md` files in `.corvia/entries/`
- **Embedding**: corvia-inference server at `http://127.0.0.1:8030` (default: nomic-embed-text-v1.5 768d; also supports all-MiniLM-L6-v2 384d)
- **MCP transport**: HTTP (`http://127.0.0.1:8020/mcp`), auto-started by devcontainer
- **Config**: `corvia.toml` at workspace root
