<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/corvia-logo-light.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/assets/corvia-logo.png">
    <img src="docs/assets/corvia-logo.png" alt="corvia" width="200">
  </picture>
</p>

# corvia demo workspace

Multi-repo workspace demonstrating [corvia](https://github.com/chunzhe10/corvia) — organizational memory for AI agents.

This workspace indexes corvia's own codebase, showcasing the knowledge management system on its own source code.

## Quick start

### Option 1: Devcontainer (recommended)

Open in GitHub Codespaces, VS Code Dev Containers, or DevPod.

### Option 2: Local

```bash
git clone https://github.com/chunzhe10/corvia-workspace
cd corvia-workspace
corvia workspace init    # clones repos, provisions Ollama
corvia workspace ingest  # indexes both repos
corvia serve --mcp &     # start server
corvia search "how does chunking work"
```

## What's inside

- **corvia** (namespace: `kernel`) — the core knowledge store, agent coordination, embedding pipeline, and adapters (including the git/tree-sitter ingestion adapter)

## Try these searches

```bash
corvia search "IngestionAdapter"          # finds trait + implementation across repos
corvia search "how does embedding work"   # surfaces pipeline from kernel
corvia search "tree-sitter chunking"      # finds adapter's AST parsing logic
corvia workspace status                   # see workspace state
```

## Fresh ingest

The workspace ships with pre-ingested knowledge. To rebuild from scratch:

```bash
corvia workspace ingest --fresh
```
