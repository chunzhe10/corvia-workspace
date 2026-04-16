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

## corvia MCP tool usage (detailed)

- Before writing or modifying code: `corvia_search` for prior decisions and patterns
- Before answering any question about the project: `corvia_search` first
- Before designing a feature: `corvia_search` for existing context and prior decisions
- After making a design decision: `corvia_write` to record it for future sessions
- After discovering non-obvious insights during a task: `corvia_write` immediately —
  do not wait to be asked. See AGENTS.md "Auto-Save Research Findings" for criteria.
- When exploring unfamiliar areas: `corvia_search` before diving into code

**Do NOT skip corvia lookups to save time.** The knowledge base exists to prevent
re-discovering things that were already decided. Always check corvia first, then
use native tools (file read, grep, bash) for code-level details.

**Superpowers skills are mandatory** for brainstorming, code review, plan execution,
and debugging. See AGENTS.md "Superpowers Plugin (Required)" for details.

## Known workarounds (Claude Code specific)

### Emergency hook bypass (CORVIA_HOOKS_DISABLED)

If `corvia hooks run` fails (e.g., binary mismatch after rebuild, missing subcommand),
**all Claude Code operations are blocked**. The hooks have two safety mechanisms:

1. **Automatic fallback**: Hook commands detect "unrecognized subcommand" errors and
   exit 0 (allow) instead of blocking. This handles binary version mismatches.
2. **Manual bypass**: Set `CORVIA_HOOKS_DISABLED=1` to skip all hooks entirely.

**To fix a bricked Claude Code session:**
```bash
# Option 1: Set env var (disables hooks for this session)
export CORVIA_HOOKS_DISABLED=1

# Option 2: Download the latest release binary
gh release download --repo chunzhe10/corvia -p "corvia-cli-linux-amd64" -D /tmp
cp /tmp/corvia-cli-linux-amd64 /usr/local/bin/corvia && chmod +x /usr/local/bin/corvia

# Option 3: Remove hooks from settings.json entirely
python3 -c "
import json, pathlib
p = pathlib.Path.home() / '.claude/settings.json'
d = json.loads(p.read_text())
d.pop('hooks', None)
p.write_text(json.dumps(d, indent=2))
print('hooks removed')
"
```

After fixing, regenerate hooks with the working binary: `corvia hooks init`

- **Root cause**: Building from a commit before the hooks migration (pre-v0.4.5)
  produces a binary without `corvia hooks`, but settings.json still references it.
- **Prevention**: Always build from the latest commit, or download release binaries.

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
echo "local-build" | sudo tee /usr/local/share/corvia-release-tag >/dev/null
corvia-dev up --no-foreground
```

**Important**: The `echo "local-build"` line invalidates the release tag cache so the
next container rebuild downloads fresh release binaries instead of keeping the local build.
If you use `corvia-dev rebuild` instead of manual `cp`, this is handled automatically.

### `corvia-dev rebuild` cmake failure

`corvia-dev rebuild` does a release build that triggers ORT source compilation
requiring cmake + CUDA toolkit. Use manual `cargo build` (debug) + binary copy
instead for iterative development.

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

## Recording Decisions

Use `corvia_write` to persist decisions. Entry fields are `id`, `created_at`, `kind`,
`supersedes`, and `tags` — there is no `source_origin` or session metadata. Use
`kind` to categorize entries (e.g., `"decision"`, `"learning"`).
