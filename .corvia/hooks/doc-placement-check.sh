#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0
case "$FILE_PATH" in *.md|*.mdx|*.rst) ;; *) exit 0 ;; esac
case "$FILE_PATH" in
  # Common root-level files — always allowed
  README.md|CLAUDE.md|AGENTS.md|CHANGELOG.md|CONTRIBUTING.md|LICENSE.md)
    exit 0 ;;
  # Agent skills and config — always allowed
  .agents/*)
    exit 0 ;;
  docs/superpowers/*)
    echo "BLOCKED: file is in blocked path 'docs/superpowers/*'. Save product docs to repos/<repo>/docs/ instead." >&2
    exit 2
    ;;
  repos/*/docs/*|docs/decisions/*|docs/learnings/*|docs/marketing/*|docs/plans/*)
    exit 0 ;;
esac
echo "NOTE: '$FILE_PATH' is in an unusual location for docs." >&2
exit 0
