#!/bin/bash
set -e

echo "=== Corvia Workspace: Starting Services ==="

# Start Ollama in background
ollama serve &
sleep 2

# Start Corvia server
corvia serve --mcp &

echo "Corvia server running on http://localhost:8020"
echo "Try: corvia search 'how does embedding work'"
