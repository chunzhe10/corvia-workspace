#!/usr/bin/env bash
# Hook: PreToolUse (Write|Edit) — enforce doc-placement rules.
# Reads JSON from stdin (Claude Code hook protocol).
# MUST NOT write to stderr — Claude Code treats any stderr as a hook error.

# Telemetry: inline capture of exit code + stderr (remove when diagnosed)
_TEL_LOG="/tmp/claude-hook-telemetry.jsonl"
_TEL_ERR=$(mktemp /tmp/_hk.XXXXXX 2>/dev/null || echo /tmp/_hk_$$)
exec 2>"$_TEL_ERR"
trap '_RC=$?; printf "{\"ts\":\"%s\",\"hook\":\"doc-placement-check\",\"rc\":%d,\"err\":\"%s\"}\n" "$(date -u +%H:%M:%S)" "$_RC" "$(tr "\n" " " < "$_TEL_ERR" 2>/dev/null)" >> "$_TEL_LOG" 2>/dev/null; rm -f "$_TEL_ERR"; exit $_RC' EXIT

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

# Strip workspace prefix to get relative path (Claude Code sends absolute paths)
FILE_PATH="${FILE_PATH#$PWD/}"

# Files outside the workspace (still absolute after stripping) are not our concern
case "$FILE_PATH" in /*) exit 0 ;; esac

# Only check documentation files
case "$FILE_PATH" in *.md|*.mdx|*.rst) ;; *) exit 0 ;; esac

case "$FILE_PATH" in
  # Common root-level files — always allowed
  README.md|CLAUDE.md|AGENTS.md|CHANGELOG.md|CONTRIBUTING.md|LICENSE.md)
    exit 0 ;;
  # Agent skills and config — always allowed
  .agents/*)
    exit 0 ;;
  docs/superpowers/*)
    echo "BLOCKED: file is in blocked path 'docs/superpowers/*'. Save product docs to repos/<repo>/docs/ instead."
    exit 2
    ;;
  repos/*/docs/*|docs/decisions/*|docs/learnings/*|docs/marketing/*|docs/plans/*)
    exit 0 ;;
esac

# Informational note — stdout only, no stderr
echo "NOTE: '$FILE_PATH' is in an unusual location for docs."
exit 0
