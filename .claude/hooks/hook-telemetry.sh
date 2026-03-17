#!/usr/bin/env bash
# Hook telemetry — source this at the TOP of every hook script (before exec 2>/dev/null).
# Captures exit code and stderr to /tmp/claude-hook-telemetry.jsonl.
# Usage: source "$(dirname "$0")/hook-telemetry.sh"
#
# Remove this file and all `source` lines once hook errors are diagnosed.

_HOOK_TEL_LOG="/tmp/claude-hook-telemetry.jsonl"
_HOOK_TEL_NAME="${BASH_SOURCE[1]##*/}"
_HOOK_TEL_STDERR_FILE=$(mktemp /tmp/_hook_err.XXXXXX 2>/dev/null || echo "/tmp/_hook_err_$$")

# Redirect stderr to temp file (captures what would go to /dev/null)
exec 2>"$_HOOK_TEL_STDERR_FILE"

# On EXIT: log hook name, exit code, stderr content, then clean up
trap '
  _HOOK_TEL_RC=$?
  _HOOK_TEL_ERR=$(head -c 500 "$_HOOK_TEL_STDERR_FILE" 2>/dev/null | tr "\n" " ")
  _HOOK_TEL_ERR_SZ=$(wc -c < "$_HOOK_TEL_STDERR_FILE" 2>/dev/null || echo 0)
  printf "{\"ts\":\"%s\",\"hook\":\"%s\",\"rc\":%d,\"stderr_bytes\":%s,\"stderr\":\"%s\"}\n" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
    "$_HOOK_TEL_NAME" \
    "$_HOOK_TEL_RC" \
    "$_HOOK_TEL_ERR_SZ" \
    "$_HOOK_TEL_ERR" \
    >> "$_HOOK_TEL_LOG" 2>/dev/null
  rm -f "$_HOOK_TEL_STDERR_FILE" 2>/dev/null
  exit $_HOOK_TEL_RC
' EXIT
