# corvia-workspace

> Multi-repo workspace for [corvia](repos/corvia) — organizational memory for AI agents.

This file follows the [AGENTS.md standard](https://agents.md/).

## Workspace Layout

```
corvia-workspace/
├── corvia.toml              # Workspace config (repos, embedding, server)
├── repos/
│   └── corvia/              # Core: kernel, server, CLI, adapters (Rust, AGPL-3.0)
├── .corvia/                 # Local knowledge store (LiteStore)
└── .claude/settings.json    # MCP server config for Claude Code
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

This workspace is configured to use corvia's own MCP server. Claude Code connects to
`http://localhost:8020/mcp` via `.claude/settings.json`. The server is started automatically
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

## Repo-Specific Instructions

For detailed build/test/architecture guidance, see:
- [repos/corvia/AGENTS.md](repos/corvia/AGENTS.md) — kernel, server, CLI, adapters

## Development

- **Language**: Rust workspace (cargo)
- **Storage**: LiteStore (default, zero-Docker) — data in `.corvia/`
- **Embedding**: corvia-inference server at `http://127.0.0.1:8030` (nomic-embed-text-v1.5, 768d)
- **API server**: `http://127.0.0.1:8020` (REST + MCP)
- **Config**: `corvia.toml` at workspace root
