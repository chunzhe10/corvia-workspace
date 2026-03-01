# Corvia Demo Workspace

Multi-repo workspace demonstrating [Corvia](https://github.com/anthropics/corvia) --- organizational reasoning memory for AI agents.

This workspace indexes Corvia's own codebase (kernel + git adapter) as two repos, showcasing cross-repo knowledge management.

## Quick Start

### Option 1: Devcontainer (recommended)

Open in GitHub Codespaces, VS Code Dev Containers, or DevPod.

### Option 2: Local

```bash
git clone https://github.com/anthropics/corvia-workspace
cd corvia-workspace
corvia workspace init    # clones repos, provisions Ollama
corvia workspace ingest  # indexes both repos
corvia serve --mcp &     # start server
corvia search "how does chunking work"
```

## What's Inside

- **corvia** (namespace: `kernel`) --- the core knowledge store, agent coordination, embedding pipeline
- **corvia-adapter-git** (namespace: `adapter`) --- git repository ingestion with tree-sitter AST chunking

## Try These Searches

```bash
corvia search "IngestionAdapter"          # finds trait + implementation across repos
corvia search "how does embedding work"   # surfaces pipeline from kernel
corvia search "tree-sitter chunking"      # finds adapter's AST parsing logic
corvia workspace status                   # see workspace state
```

## Fresh Ingest

The workspace ships with pre-ingested knowledge. To rebuild from scratch:

```bash
corvia workspace ingest --fresh
```
