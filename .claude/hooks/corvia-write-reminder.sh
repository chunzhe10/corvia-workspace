#!/bin/bash
# PostToolUse hook: remind to write decisions/learnings to corvia after git commits.
# Reads JSON from stdin (Claude Code hook protocol).

# Telemetry: inline capture of exit code + stderr (remove when diagnosed)
_TEL_LOG="/tmp/claude-hook-telemetry.jsonl"
_TEL_ERR=$(mktemp /tmp/_hk.XXXXXX 2>/dev/null || echo /tmp/_hk_$$)
exec 2>"$_TEL_ERR"
trap '_RC=$?; printf "{\"ts\":\"%s\",\"hook\":\"corvia-write-reminder\",\"rc\":%d,\"err\":\"%s\"}\n" "$(date -u +%H:%M:%S)" "$_RC" "$(tr "\n" " " < "$_TEL_ERR" 2>/dev/null)" >> "$_TEL_LOG" 2>/dev/null; rm -f "$_TEL_ERR"; exit $_RC' EXIT

# Extract fields from JSON. tool_response may be a string or object,
# so we guard the nested access with `objects //` to avoid jq errors.
eval "$(jq -r '
  @sh "COMMAND=\(.tool_input.command // "")",
  @sh "EXIT_CODE=\((.tool_response | objects | .exitCode // .exit_code) // 0)"
')" || exit 0

# Only trigger on successful git commit commands
case "$COMMAND" in
    *"git commit "*)
        [ "$EXIT_CODE" != "0" ] && exit 0
        echo "REMINDER: You just committed code. If this commit contains a design decision, architectural change, or notable learning, persist it with corvia_write (scope_id: corvia, agent_id: claude-code). Skip if the commit is trivial (typo fix, formatting, etc.)."
        ;;
esac

exit 0
