# corvia-workspace

> Multi-repo workspace for [corvia](repos/corvia) — organizational memory for AI agents.

This file follows the [AGENTS.md standard](https://agents.md/).

## Workspace Layout

```
corvia-workspace/
├── AGENTS.md                # Cross-platform AI agent instructions (this file)
├── CLAUDE.md                # Claude Code wrapper (imports AGENTS.md)
├── corvia.toml              # Workspace config (repos, embedding, server)
├── .agents/                 # Agent-agnostic skills & reference docs
│   └── skills/              # Reusable patterns for any AI assistant
├── .mcp.json                # MCP server config (Claude Code, Codex, etc.)
├── repos/
│   └── corvia/              # Core: kernel, server, CLI, adapters (Rust, AGPL-3.0)
├── .corvia/                 # Local knowledge store (LiteStore)
└── docs/plans/              # Design documents
```

## Quick Reference

```bash
corvia workspace status          # Check workspace + service health
corvia search "query"            # Search ingested knowledge
corvia workspace ingest          # Index all repos
corvia workspace ingest --fresh  # Re-index from scratch
corvia serve &                   # Start server (auto-started by devcontainer)
```

## MCP Server (Dogfooding)

This workspace uses corvia's own MCP server at `http://localhost:8020/mcp`.
Any MCP-compatible AI tool can connect to it. The server is started automatically
by the devcontainer's `post-start.sh`.

Available MCP tools:
- `corvia_search` — semantic search across ingested knowledge
- `corvia_write` — write knowledge entries (requires agent identity)
- `corvia_history` — entry supersession history
- `corvia_graph` — graph edges for an entry
- `corvia_reason` — run health checks on a scope
- `corvia_agent_status` — agent contribution summary
- `corvia_context` — retrieve assembled context (RAG retrieval only)
- `corvia_ask` — full RAG: question → AI-generated answer from knowledge

## Hybrid Tool Usage (corvia MCP + native tools)

Use **both** corvia MCP tools and your native tools (file read/write, search, terminal).
They serve different purposes and are strongest together.

### When to use corvia MCP tools

- **Starting a task**: Call `corvia_search` or `corvia_ask` first to find prior decisions,
  design context, or patterns relevant to the work.
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
> When in doubt, check corvia first — it's fast and may save you from re-discovering
> something that was already decided.

## AI Development Learnings

This workspace incorporates proven patterns from community best practices.
See [.agents/skills/ai-assisted-development.md](.agents/skills/ai-assisted-development.md)
for the full reference.

Key principles applied here:
- **Context engineering > prompt engineering** — AGENTS.md is essential infrastructure
- **Verify explicitly** — give pass/fail criteria, run tests before claiming success
- **Guard context** — delegate research to subagents, compact proactively, fresh sessions per task
- **Record decisions** — use `corvia_write` to persist learnings (dogfood the product)

## Repo-Specific Instructions

For detailed build/test/architecture guidance, see:
- [repos/corvia/AGENTS.md](repos/corvia/AGENTS.md) — kernel, server, CLI, adapters

## Development

- **Language**: Rust workspace (cargo)
- **Storage**: LiteStore (default, zero-Docker) — data in `.corvia/`
- **Embedding**: corvia-inference server at `http://127.0.0.1:8030` (nomic-embed-text-v1.5, 768d)
- **API server**: `http://127.0.0.1:8020` (REST + MCP)
- **Config**: `corvia.toml` at workspace root
