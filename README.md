<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/corvia-logo-light.png">
    <source media="(prefers-color-scheme: light)" srcset="docs/assets/corvia-logo.png">
    <img src="docs/assets/corvia-logo.png" alt="corvia" width="200">
  </picture>
</p>

# corvia development workspace

Multi-repo workspace for developing [corvia](repos/corvia) — organizational memory
for AI agents. This workspace dogfoods corvia's own MCP server and knowledge store
on its own source code.

## Services

| Service | URL | Description |
|---------|-----|-------------|
| **API server + Dashboard** | `http://localhost:8020` | REST + MCP protocol server + embedded dashboard |
| **Vite dev server** | `http://localhost:8021` | Dashboard hot-reload (dev only) |
| **Inference** | `http://localhost:8030` | gRPC embedding + chat (ONNX Runtime) |

All services start automatically in the devcontainer via `post-start.sh`.

## Quick start

### Option 1: Devcontainer (recommended)

Open in GitHub Codespaces, VS Code Dev Containers, or DevPod. Everything is
pre-configured — services start automatically.

### Option 2: Local

```bash
git clone https://github.com/chunzhe10/corvia-workspace
cd corvia-workspace
corvia init --yes              # initialize .corvia/ store
corvia ingest                  # index the current workspace
corvia serve &                 # start HTTP MCP server on :8020
corvia search "how does chunking work"
```

## What's inside

- **[corvia](repos/corvia)** (namespace: `kernel`) — core knowledge store, agent
  coordination, embedding pipeline, inference server, adapters, dashboard, and CLI

## MCP server

The workspace MCP server at `http://localhost:8020/mcp` provides 18 tools for
knowledge operations. Any MCP-compatible AI tool (Claude Code, Codex CLI, etc.)
can connect. Default embedding uses `corvia-inference` with ONNX Runtime —
no Ollama required.

## Try these searches

```bash
corvia search "IngestionAdapter"          # finds trait + implementation
corvia search "how does embedding work"   # surfaces pipeline from kernel
corvia search "tree-sitter chunking"      # finds adapter's AST parsing
corvia status                             # indexed entries + recent traces
```

## Fresh ingest

```bash
corvia ingest --fresh
```
