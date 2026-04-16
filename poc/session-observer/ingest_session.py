#!/usr/bin/env python3
"""POC: Ingest a Claude Code session log into corvia via MCP.

Reads a JSONL session file, groups messages into turns (user prompt -> assistant
response cycle), captures the full turn context (prompt, reasoning, tool calls,
results, response), and writes each turn to corvia through a single MCP stdio
connection.

Usage:
    python3 ingest_session.py <session.jsonl> [--dry-run] [--limit N]

This is a standalone script — does not touch corvia core.
All writes go through the MCP protocol (single access path).
"""
import json
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path


# ──────────────────────────────────────────────────────────────
# Session parsing (adapter: Claude Code JSONL)
# ──────────────────────────────────────────────────────────────

@dataclass
class ToolCall:
    """A single tool invocation within a turn."""
    name: str = ""
    file_path: str = ""
    command: str = ""
    pattern: str = ""
    query: str = ""
    result_preview: str = ""
    is_error: bool = False


@dataclass
class Turn:
    """One complete turn: user prompt -> thinking -> tool calls -> assistant response."""
    user_text: str = ""
    thinking_text: str = ""
    assistant_text: str = ""
    tool_calls: list[ToolCall] = field(default_factory=list)
    timestamp: str = ""
    session_id: str = ""
    git_branch: str = ""
    model: str = ""


def parse_session(path: Path) -> list[Turn]:
    """Parse a Claude Code JSONL session into turns."""
    turns: list[Turn] = []
    current_turn = Turn()
    pending_tools: dict[str, int] = {}

    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            msg_type = obj.get("type", "")

            if msg_type == "user":
                msg = obj.get("message", {})
                if not isinstance(msg, dict):
                    continue
                content = msg.get("content", "")

                if isinstance(content, str) and content.strip():
                    if current_turn.assistant_text or current_turn.tool_calls:
                        turns.append(current_turn)
                    current_turn = Turn(
                        user_text=content,
                        session_id=obj.get("sessionId", ""),
                        timestamp=obj.get("timestamp", ""),
                        git_branch=obj.get("gitBranch", ""),
                    )
                    pending_tools.clear()

                elif isinstance(content, list):
                    for block in content:
                        if not isinstance(block, dict):
                            continue
                        if block.get("type") == "tool_result":
                            tool_id = block.get("tool_use_id", "")
                            is_error = block.get("is_error", False)
                            result_content = block.get("content", "")
                            if isinstance(result_content, list):
                                texts = [
                                    c.get("text", "")
                                    for c in result_content
                                    if isinstance(c, dict) and c.get("type") == "text"
                                ]
                                result_content = "\n".join(texts)
                            if tool_id in pending_tools:
                                tc = current_turn.tool_calls[pending_tools[tool_id]]
                                tc.is_error = is_error
                                if isinstance(result_content, str):
                                    tc.result_preview = result_content[:300]

            elif msg_type == "assistant":
                msg = obj.get("message", {})
                if not isinstance(msg, dict):
                    continue
                content = msg.get("content", [])
                if not isinstance(content, list):
                    continue

                if not current_turn.model:
                    current_turn.model = msg.get("model", "")

                for block in content:
                    if not isinstance(block, dict):
                        continue
                    block_type = block.get("type", "")

                    if block_type == "thinking":
                        text = block.get("thinking", "").strip()
                        if text:
                            if current_turn.thinking_text:
                                current_turn.thinking_text += "\n"
                            current_turn.thinking_text += text

                    elif block_type == "text":
                        text = block.get("text", "").strip()
                        if text:
                            if current_turn.assistant_text:
                                current_turn.assistant_text += "\n\n"
                            current_turn.assistant_text += text

                    elif block_type == "tool_use":
                        tc = ToolCall(name=block.get("name", ""))
                        inp = block.get("input", {})
                        if isinstance(inp, dict):
                            tc.file_path = inp.get("file_path", "") or inp.get("path", "")
                            tc.command = inp.get("command", "")
                            tc.pattern = inp.get("pattern", "")
                            tc.query = inp.get("query", "")
                        idx = len(current_turn.tool_calls)
                        current_turn.tool_calls.append(tc)
                        tool_id = block.get("id", "")
                        if tool_id:
                            pending_tools[tool_id] = idx

                if not current_turn.timestamp:
                    current_turn.timestamp = obj.get("timestamp", "")

    if current_turn.assistant_text or current_turn.tool_calls:
        turns.append(current_turn)

    return turns


# ──────────────────────────────────────────────────────────────
# Turn formatting
# ──────────────────────────────────────────────────────────────

def format_tool_call(tc: ToolCall) -> str:
    parts = [tc.name]
    if tc.file_path:
        parts.append(tc.file_path)
    elif tc.command:
        cmd = tc.command[:120] + "..." if len(tc.command) > 120 else tc.command
        parts.append(f"`{cmd}`")
    elif tc.pattern:
        parts.append(f"/{tc.pattern}/")
    elif tc.query:
        parts.append(f'"{tc.query}"')

    line = " -> ".join(parts)
    if tc.is_error:
        line += " [ERROR]"
    elif tc.result_preview:
        preview = tc.result_preview.replace("\n", " ").strip()
        if len(preview) > 100:
            preview = preview[:100] + "..."
        if preview:
            line += f" -> {preview}"
    return line


def format_turn_content(turn: Turn) -> str:
    sections = []

    if turn.user_text:
        user = turn.user_text
        if len(user) > 500:
            user = user[:500] + " [...]"
        sections.append(f"## Prompt\n{user}")

    if turn.thinking_text:
        thinking = turn.thinking_text
        if len(thinking) > 800:
            thinking = thinking[:800] + " [...]"
        sections.append(f"## Reasoning\n{thinking}")

    if turn.tool_calls:
        lines = [f"- {format_tool_call(tc)}" for tc in turn.tool_calls]
        sections.append(f"## Actions\n" + "\n".join(lines))

    if turn.assistant_text:
        text = turn.assistant_text
        if len(text) > 2000:
            text = text[:2000] + "\n\n[truncated]"
        sections.append(f"## Response\n{text}")

    return "\n\n".join(sections)


def build_tags(turn: Turn, session_file: str) -> list[str]:
    tags = ["source:session-observer", "harness:claude-code"]
    if turn.session_id:
        tags.append(f"session:{turn.session_id[:8]}")
    if turn.git_branch:
        tags.append(f"branch:{turn.git_branch}")
    if turn.model:
        model = turn.model.split("/")[-1][:30]
        tags.append(f"model:{model}")
    tool_names = list(dict.fromkeys(tc.name for tc in turn.tool_calls))
    if tool_names:
        tags.append(f"tools:{'+'.join(tool_names[:5])}")
    if any(tc.is_error for tc in turn.tool_calls):
        tags.append("has-error")
    tags.append(f"file:{Path(session_file).stem[:8]}")
    return tags


# ──────────────────────────────────────────────────────────────
# MCP client (single stdio connection to corvia mcp)
# ──────────────────────────────────────────────────────────────

class McpClient:
    """Minimal MCP stdio client for corvia."""

    def __init__(self):
        self.proc = None
        self._next_id = 1

    def connect(self):
        self.proc = subprocess.Popen(
            ["corvia", "mcp"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        # Initialize
        resp = self._call("initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "session-observer", "version": "0.1.0"},
        })
        if "error" in resp:
            raise RuntimeError(f"MCP init failed: {resp['error']}")

        # Send initialized notification
        self._notify("notifications/initialized")
        return self

    def write(self, content: str, kind: str = "learning", tags: list[str] | None = None) -> dict:
        args = {"content": content, "kind": kind}
        if tags:
            args["tags"] = tags
        return self._call("tools/call", {"name": "corvia_write", "arguments": args})

    def close(self):
        if self.proc:
            self.proc.stdin.close()
            self.proc.wait(timeout=10)
            self.proc = None

    def _call(self, method: str, params: dict) -> dict:
        msg_id = self._next_id
        self._next_id += 1
        req = json.dumps({"jsonrpc": "2.0", "id": msg_id, "method": method, "params": params})
        self.proc.stdin.write(req + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line:
            return {"error": "EOF from MCP server"}
        return json.loads(line)

    def _notify(self, method: str, params: dict | None = None):
        msg = {"jsonrpc": "2.0", "method": method}
        if params:
            msg["params"] = params
        self.proc.stdin.write(json.dumps(msg) + "\n")
        self.proc.stdin.flush()

    def __enter__(self):
        return self.connect()

    def __exit__(self, *_):
        self.close()


# ──────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────

def main():
    import argparse
    import time

    parser = argparse.ArgumentParser(description="Ingest Claude Code session into corvia via MCP")
    parser.add_argument("session_file", help="Path to .jsonl session file")
    parser.add_argument("--dry-run", action="store_true", help="Print what would be written")
    parser.add_argument("--limit", type=int, default=0, help="Max turns to ingest (0=all)")
    parser.add_argument("--min-length", type=int, default=50,
                        help="Skip turns with total content shorter than N chars")
    args = parser.parse_args()

    path = Path(args.session_file)
    if not path.exists():
        print(f"error: {path} not found", file=sys.stderr)
        sys.exit(1)

    print(f"Parsing {path.name} ({path.stat().st_size / 1024:.0f} KB)...")
    turns = parse_session(path)
    print(f"Found {len(turns)} turns")

    def turn_length(t: Turn) -> int:
        return len(t.user_text) + len(t.assistant_text) + len(t.thinking_text) + sum(
            len(tc.name) + len(tc.result_preview) for tc in t.tool_calls
        )

    turns = [t for t in turns if turn_length(t) >= args.min_length]
    print(f"After filtering (>={args.min_length} chars): {len(turns)} turns")

    if args.limit:
        turns = turns[:args.limit]
        print(f"Limited to {args.limit} turns")

    total_tools = sum(len(t.tool_calls) for t in turns)
    with_thinking = sum(1 for t in turns if t.thinking_text)
    with_errors = sum(1 for t in turns if any(tc.is_error for tc in t.tool_calls))
    print(f"Stats: {total_tools} tool calls, {with_thinking} with thinking, {with_errors} with errors")

    if args.dry_run:
        for i, turn in enumerate(turns):
            content = format_turn_content(turn)
            tags = build_tags(turn, str(path))
            print(f"\nTurn {i+1}/{len(turns)} ({len(content)} chars, {len(turn.tool_calls)} tools):")
            print(f"  tags=[{', '.join(tags)}]")
            print(f"  content={content[:150].replace(chr(10), ' ')}...")
        print(f"\nDone: {len(turns)} turns (dry run)")
        return

    # Single MCP connection for all writes
    t0 = time.monotonic()
    written = 0
    failed = 0

    with McpClient() as mcp:
        connect_time = time.monotonic() - t0
        print(f"MCP connected ({connect_time:.1f}s)")

        for i, turn in enumerate(turns):
            content = format_turn_content(turn)
            tags = build_tags(turn, str(path))
            print(f"\nTurn {i+1}/{len(turns)} ({len(content)} chars, {len(turn.tool_calls)} tools):")

            t1 = time.monotonic()
            resp = mcp.write(content, kind="learning", tags=tags)
            elapsed = time.monotonic() - t1

            result = resp.get("result", {})
            # MCP tools/call returns result.content array
            result_content = result.get("content", [])
            if isinstance(result_content, list) and result_content:
                text = result_content[0].get("text", "")
                # Extract entry ID or dedup message
                if "created" in text.lower() or "superseded" in text.lower():
                    print(f"  {text.strip()[:120]} ({elapsed:.2f}s)")
                    written += 1
                elif "duplicate" in text.lower() or "similar" in text.lower():
                    print(f"  [dedup] {text.strip()[:100]} ({elapsed:.2f}s)")
                    written += 1
                else:
                    print(f"  {text.strip()[:120]} ({elapsed:.2f}s)")
                    written += 1
            elif "error" in resp:
                print(f"  [error] {resp['error']} ({elapsed:.2f}s)")
                failed += 1
            else:
                print(f"  [unknown response] ({elapsed:.2f}s)")
                failed += 1

    total_time = time.monotonic() - t0
    print(f"\nDone: {written} written, {failed} failed ({total_time:.1f}s total)")


if __name__ == "__main__":
    main()
