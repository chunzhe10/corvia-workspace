# corvia-workspace — Claude Code

## STOP — Read this FIRST before doing ANYTHING

**Your FIRST tool call in EVERY conversation and EVERY new task MUST be a corvia MCP
tool** (`corvia_search`, `corvia_ask`, or `corvia_context`). This overrides your
default behavior of reaching for Grep/Glob/Read first.

**DO NOT use Grep, Glob, or code search as your first action.** Always query corvia
for project context before touching code. The order is:

1. `corvia_search` or `corvia_ask` — get project knowledge and prior decisions
2. THEN use Grep/Glob/Read for code-level details

This is the single most important instruction in this file. If you skip corvia and
go straight to code search, you are violating this project's workflow.

@AGENTS.md

## corvia MCP tool usage (detailed)

- Before writing or modifying code: `corvia_search` for prior decisions and patterns
- Before answering any question about the project: `corvia_ask` first
- Before designing a feature: `corvia_search` + `corvia_context` for existing context
- After making a design decision: `corvia_write` to record it for future sessions
- After discovering non-obvious insights during a task: `corvia_write` immediately —
  do not wait to be asked. See AGENTS.md "Auto-Save Research Findings" for criteria.
- When exploring unfamiliar areas: `corvia_ask` before diving into code

**Do NOT skip corvia lookups to save time.** The knowledge base exists to prevent
re-discovering things that were already decided. Always check corvia first, then
use native tools (file read, grep, bash) for code-level details.

**Superpowers skills are mandatory** for brainstorming, code review, plan execution,
and debugging. See AGENTS.md "Superpowers Plugin (Required)" for details.

## Known workarounds (Claude Code specific)

### WSL memory leak from orphaned processes

Claude Code leaks memory in WSL via orphaned node processes that persist after
sessions close. The `corvia hooks run --event SessionEnd` handler includes an
orphan cleanup module (`cleanup.rs`) that kills these orphans on exit.

- **Scope**: Claude Code on WSL only — not a corvia product concern
- **Handler**: `crates/corvia-cli/src/hooks/cleanup.rs` (throttled to once per 10min)
- **Upstream**: https://github.com/anthropics/claude-code/issues
- **Remove when**: upstream fix lands in Claude Code

### Server restart procedure (corvia-dev)

`corvia-dev restart` can leave orphaned processes holding ports. Always use:
```bash
corvia-dev down
sleep 3
# If needed: pkill -9 -f "corvia serve" to kill lingering processes
corvia-dev up --no-foreground
```

Never use `corvia-dev restart` for binary updates. Instead:
```bash
cargo build
corvia-dev down && sleep 3
cp target/debug/corvia /usr/local/bin/corvia
corvia-dev up --no-foreground
```

### `corvia-dev rebuild` cmake failure

`corvia-dev rebuild` does a release build that triggers ORT source compilation
requiring cmake + CUDA toolkit. Use manual `cargo build` (debug) + binary copy
instead for iterative development.

## Autonomous Development Protocol

For autonomous sessions (owner away), import `@CLAUDE-AUTONOMOUS.md` which provides:
- Pre-implementation review gate (Research → Design → 3-Persona Review → Plan → Implement)
- Session logging, commit cadence, error recovery
- Setback recording and learning persistence
- Benchmark and milestone evaluation protocols

## Documentation Save Locations

- Product-specific designs and RFCs → `repos/corvia/docs/rfcs/`
- Workspace-level decisions → `docs/decisions/`
- Implementation plans → alongside their design doc in the repo
- Learnings → `docs/learnings/`
- Marketing content → `docs/marketing/`

Do NOT create `docs/superpowers/` — that path is blocked by enforcement hooks.

## Recording Decisions

Use `corvia_write` with `content_role` and `source_origin` params:
- corvia product decisions: `source_origin = "repo:corvia"`
- Workspace decisions: `source_origin = "workspace"`
