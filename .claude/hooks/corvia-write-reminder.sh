#!/bin/bash
# PostToolUse hook: remind to write decisions/learnings to corvia after git commits.
# Reads JSON from stdin (Claude Code hook protocol).
#
# Edge cases handled:
#   - Failed commits (non-zero exit): no reminder
#   - jq missing: graceful fallback to grep on raw JSON
#   - False positives (e.g. grep "git commit"): reduced by anchoring pattern
#   - Performance: early-exit on stdin read if no "git commit" present

# Suppress all stderr — Claude Code treats any stderr as a hook error
exec 2>/dev/null

# Read stdin once
INPUT=$(cat)

# Fast path: skip jq entirely if "git commit" not in the payload
echo "$INPUT" | grep -q 'git commit' || exit 0

# Extract command — try jq, fall back to grep
if command -v jq >/dev/null 2>&1; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
    EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exitCode // .tool_response.exit_code // "0"')
else
    # Rough fallback: extract command value from JSON
    COMMAND=$(echo "$INPUT" | grep -oP '"command"\s*:\s*"\K[^"]+' || true)
    EXIT_CODE="0"
fi

# Only trigger on actual git commit commands (anchored to start or after && / ;)
if echo "$COMMAND" | grep -qE '(^|&&\s*|;\s*)git commit '; then
    # Skip if the commit failed
    if [ "$EXIT_CODE" != "0" ]; then
        exit 0
    fi
    echo "REMINDER: You just committed code. If this commit contains a design decision, architectural change, or notable learning, persist it with corvia_write (scope_id: corvia, agent_id: claude-code). Skip if the commit is trivial (typo fix, formatting, etc.)."
fi

exit 0
