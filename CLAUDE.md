# corvia-workspace — Claude Code

@AGENTS.md

## MANDATORY: Always use corvia MCP tools

**You MUST call corvia MCP tools (corvia_search, corvia_ask, corvia_context) at the
start of every development task, question, or investigation.** This is not optional.

- Before writing or modifying code: `corvia_search` for prior decisions and patterns
- Before answering any question about the project: `corvia_ask` first
- Before designing a feature: `corvia_search` + `corvia_context` for existing context
- After making a design decision: `corvia_write` to record it for future sessions
- When exploring unfamiliar areas: `corvia_ask` before diving into code

**Do NOT skip corvia lookups to save time.** The knowledge base exists to prevent
re-discovering things that were already decided. Always check corvia first, then
use native tools (file read, grep, bash) for code-level details.
