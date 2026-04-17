# corvia-workspace — Claude Code

## STOP — Read this FIRST before doing ANYTHING

**Your FIRST tool call in EVERY conversation and EVERY new task MUST be a corvia MCP
tool** (`corvia_search` or `corvia_write`). This overrides your default behavior of
reaching for Grep/Glob/Read first.

**DO NOT use Grep, Glob, or code search as your first action.** Always query corvia
for project context before touching code. The order is:

1. `corvia_search` — get project knowledge and prior decisions
2. THEN use Grep/Glob/Read for code-level details

This is the single most important instruction in this file. If you skip corvia and
go straight to code search, you are violating this project's workflow.

@AGENTS.md

**Superpowers skills are mandatory** for brainstorming, code review, plan execution,
and debugging. See AGENTS.md "Superpowers Plugin (Required)" for details.

For corvia usage patterns and the hybrid tool table, see AGENTS.md "Hybrid Tool Usage".

## Known Workarounds

**Bricked by hooks:** If `corvia hooks run` fails and blocks all tools: `export CORVIA_HOOKS_DISABLED=1` (session bypass), or redownload: `gh release download --repo chunzhe10/corvia -p corvia-cli-linux-amd64 -D /tmp && cp /tmp/corvia-cli-linux-amd64 /usr/local/bin/corvia && chmod +x /usr/local/bin/corvia`.

**Server restart (corvia-dev):** Never use `corvia-dev restart` — orphans processes. Use: `corvia-dev down && sleep 3 && pkill -9 -f "corvia serve" 2>/dev/null; corvia-dev up --no-foreground`. Binary update: `cargo build` → down → `cp target/debug/corvia /usr/local/bin/corvia` → `echo "local-build" | sudo tee /usr/local/share/corvia-release-tag >/dev/null` → up.

**`corvia-dev rebuild`:** Triggers cmake/CUDA compilation — use `cargo build` (debug) + binary copy instead.

## Autonomous Development Protocol

For autonomous sessions (owner away), import `@.claude/CLAUDE-AUTONOMOUS.md` which provides:
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

## Model Selection

Default model: opus (set in `~/.claude/settings.json`).

| Task type | Model |
|-----------|-------|
| Standalone info queries, read-only exploration | `/model haiku` |
| Routine coding, execution, refactoring | `/model sonnet` |
| Design, review, debugging, E2E (default) | opus |

If the cost of missing something exceeds the cost of a token, use opus.

