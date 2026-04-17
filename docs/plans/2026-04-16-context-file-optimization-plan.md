# Context File Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trim ~2,470 tokens from CLAUDE.md/AGENTS.md, add model selection guidance, upgrade dev-loop review/E2E phases to opus, and set opus as the default model.

**Architecture:** Six independent edit tasks — CLAUDE.md trim, two content moves (BKMs to destination files), AGENTS.md trim, three dev-loop model upgrades, and one settings change. No code changes; all edits are to documentation and configuration files.

**Tech Stack:** Markdown files, JSON config, Edit/Write tools.

**Design spec:** `docs/plans/2026-04-16-context-file-optimization-design.md`

---

## File Map

| File | Action |
|------|--------|
| `CLAUDE.md` | Remove 5 sections, compress 2, add Model Selection |
| `AGENTS.md` | Collapse Hybrid Tool Usage, delete AI Learnings, replace 2 BKM sections with pointers |
| `.claude/CLAUDE-AUTONOMOUS.md` | Append Self-Running Agent BKMs section |
| `docs/references/production-agent-bkms.md` | **New file** — receives Production Agent BKMs |
| `.agents/skills/dev-loop/phases/REVIEW-DISPATCH.md` | `sonnet` → `opus` |
| `.agents/skills/dev-loop/FIVE-PERSONA-REVIEWER.md` | `sonnet` → `opus` |
| `.agents/skills/dev-loop/E2E-TESTER.md` | `sonnet` → `opus` |
| `~/.claude/settings.json` | `"model": "sonnet"` → `"model": "opus"` |

---

## Task 1: Trim CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

Remove 5 sections and compress 2, then add Model Selection. Make all edits to `CLAUDE.md` in this task.

- [ ] **Step 1: Delete `corvia MCP tool usage (detailed)` section and compress to pointer**

Replace this entire block (lines 20–35):
```
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
```

With:
```
**Superpowers skills are mandatory** for brainstorming, code review, plan execution,
and debugging. See AGENTS.md "Superpowers Plugin (Required)" for details.

For corvia usage patterns and the hybrid tool table, see AGENTS.md "Hybrid Tool Usage".
```

- [ ] **Step 2: Replace the entire `Known workarounds` section with a compressed version**

Replace this entire block (lines 37–113, from `## Known workarounds` through the cmake section):
```
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
```

With:
```
## Known Workarounds

**Server restart (corvia-dev):** Never use `corvia-dev restart` — orphans processes. Use: `corvia-dev down && sleep 3 && corvia-dev up --no-foreground`. Binary update: `cargo build` → down → `cp target/debug/corvia /usr/local/bin/corvia` → `echo "local-build" | sudo tee /usr/local/share/corvia-release-tag >/dev/null` → up.

**`corvia-dev rebuild`:** Triggers cmake/CUDA compilation — use `cargo build` (debug) + binary copy instead.
```

- [ ] **Step 3: Delete the `Recording Decisions` section**

Remove this entire block:
```
## Recording Decisions

Use `corvia_write` to persist decisions. Entry fields are `id`, `created_at`, `kind`,
`supersedes`, and `tags` — there is no `source_origin` or session metadata. Use
`kind` to categorize entries (e.g., `"decision"`, `"learning"`).
```

(The section ends at the end of the file — delete it entirely, the file ends after this block.)

- [ ] **Step 4: Add `Model Selection` section**

The file now ends after `Documentation Save Locations`. Append this block at the end:
```
## Model Selection

Default model: opus (set in `~/.claude/settings.json`).

| Task type | Model |
|-----------|-------|
| Info gathering, corvia lookups, quick questions | `/model haiku` |
| Routine coding, execution, refactoring | `/model sonnet` |
| Design, review, debugging, E2E (default) | opus |

If the cost of missing something exceeds the cost of a token, use opus.
```

- [ ] **Step 5: Verify CLAUDE.md looks correct**

```bash
wc -l CLAUDE.md
grep -n "Emergency hook bypass\|WSL memory\|Recording Decisions\|corvia MCP tool usage (detailed)" CLAUDE.md
grep -n "Model Selection\|Known Workarounds\|corvia-dev" CLAUDE.md
```

Expected: no matches for deleted sections; matches for new/kept sections. Line count should be roughly 55–65 lines (down from 137).

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: trim CLAUDE.md — remove dead sections, add model selection guidance"
```

---

## Task 2: Create `docs/references/production-agent-bkms.md`

**Files:**
- Create: `docs/references/production-agent-bkms.md`

Move the Production Agent BKMs content out of AGENTS.md into its own reference file.

- [ ] **Step 1: Create the directory and file**

Create `docs/references/production-agent-bkms.md` with this exact content:

```markdown
# Production Agent BKMs

Best Known Methods for building production-grade AI agents, adapted from
[agents-towards-production](https://github.com/NirDiamant/agents-towards-production).

## Architecture

- **Graph-based orchestration**: Use directed graph architectures with explicit state
  transitions for multi-step workflows. Avoid linear chains for anything non-trivial.
- **Layered separation of concerns**: Keep orchestration, memory, tools, security, and
  evaluation as distinct layers. Do not mix tool-calling logic with reasoning logic.
- **Protocol-first integration**: Adopt MCP for tool integration and A2A for multi-agent
  communication. Protocol-based design makes agents composable and replaceable.

## Memory Systems

- **Dual-memory architecture**: Short-term (session/conversation context) + long-term
  (persistent knowledge with semantic search — this is what corvia provides).
- **Self-improving memory**: Design memory that evolves through interaction — automatic
  insight extraction, conflict resolution, and knowledge consolidation across sessions.

## Security (Defense-in-Depth)

- **Three-layer guardrails**: Input validation (prompt injection prevention), behavioral
  constraints (during execution), and output filtering (before delivery to user).
- **Tool access control**: Restrict which tools an agent can invoke based on user context
  and permissions. Never give agents unrestricted access to external tools.
- **User isolation**: Prevent cross-user data leakage in multi-user deployments.

## Observability

- **Trace every decision point**: Capture the full reasoning chain — which tools were
  called, what the LLM decided, timing data for each step.
- **Instrument from day one**: Do not bolt on observability later. Traces are essential
  for debugging, performance analysis, and evaluation.
- **Monitor cost, latency, accuracy** continuously, not just during development.

## Evaluation & Testing

- **Domain-specific test suites**: Build evaluation sets tailored to your domain.
  Generic benchmarks are insufficient.
- **Multi-dimensional metrics**: Evaluate beyond accuracy — include cost per interaction,
  latency, safety compliance, and tool-use correctness.
- **Iterative improvement cycles**: Evaluation should produce actionable insights that
  feed back into agent refinement.

## Deployment Strategy

- **Containerize everything**: Docker for portability and environment consistency.
- **Start stateless, migrate to persistent**: Prototype without memory, then layer in
  persistence once the workflow is stable.
- **Production readiness progression**: Prototype → Functional (add memory, auth, tracing)
  → Production (guardrails, evaluation, observability) → Scaled (multi-agent, GPU, fine-tuning).
```

- [ ] **Step 2: Verify file exists**

```bash
cat docs/references/production-agent-bkms.md | head -5
```

Expected: first 5 lines of the file, starting with `# Production Agent BKMs`.

- [ ] **Step 3: Commit**

```bash
git add docs/references/production-agent-bkms.md
git commit -m "docs: extract production agent BKMs to docs/references/"
```

---

## Task 3: Append Self-Running BKMs to `.claude/CLAUDE-AUTONOMOUS.md`

**Files:**
- Modify: `.claude/CLAUDE-AUTONOMOUS.md`

Append the Self-Running Agent BKMs content (currently in AGENTS.md lines 161–241) to the end of CLAUDE-AUTONOMOUS.md. The final line of AGENTS.md's BKMs section ("For the full autonomous protocol, see CLAUDE-AUTONOMOUS.md") is a self-reference — omit it.

- [ ] **Step 1: Append the Self-Running BKMs section to `.claude/CLAUDE-AUTONOMOUS.md`**

Add this block at the very end of the file (after the last line `- Use "surprised me" language in findings`):

```markdown

## Self-Running Agent BKMs

Best Known Methods for autonomous, long-running Claude Code sessions. Adapted from
[Anthropic engineering](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents),
[self-improving agents](https://addyosmani.com/blog/self-improving-agents/), and
[obra/superpowers](https://github.com/obra/superpowers).

### Session Continuity & Progress Tracking

- **Progress file**: Maintain a session log (`docs/session-logs/<date>-<task>.md`)
  with hard fails, decisions, and checkpoints. Enables context recovery across sessions.
- **Git-based state**: Commit after every logical unit of work with descriptive messages.
  Git history becomes the primary memory mechanism between sessions.
- **JSON for critical state**: Use JSON over markdown for state files that agents
  modify — models are less likely to corrupt structured data.
- **Single-feature focus**: Work on one feature/fix at a time. Complete it fully
  (implement → test → verify → commit) before moving to the next.

### Autonomous Execution Loop

```
1. Health check (build + tests pass?)
2. Read session log / progress file
3. corvia_search for relevant context
4. Pick next task (smallest unblocked item)
5. Implement with verification criteria defined upfront
6. Run tests + manual verification
7. Multi-persona review (SWE / PM / QA)
8. Commit + update session log
9. Record findings to corvia (corvia_write)
10. Repeat or hand off
```

### Multi-Persona Review Gate

Every non-trivial change is reviewed through **five** independent lenses before commit.
Three are standard; two are dynamic based on the task (see `dev-loop` skill for selection table):

**Standard (always present):**
- **Senior SWE**: Correctness, safety, idiomatic patterns, edge cases, performance
- **Product Manager**: Goal alignment, UX coherence, milestone advancement, scope
- **QA Engineer**: Test coverage, E2E verification, failure modes, regression risk

**Dynamic (task-dependent, select two):**
- Chosen based on issue labels and changed files (e.g., Security Engineer for auth work,
  Performance Engineer for optimization, UX Designer for dashboard changes)

Each reviewer MUST be a deep, independent subagent run — not a shallow one-liner.
Reviews producing less than 10 lines of substantive feedback are invalid.

### Error Recovery

- **Never retry blindly** — diagnose root cause first
- **Log every failure** in the session log with full context
- **Fix forward** — address the underlying issue, not just the symptom
- **Verify the fix** with a test that would have caught the original bug
- **Record in corvia** so future sessions don't hit the same issue

### Parallelization

- **Subagents for research** — delegate broad exploration to background agents
- **Worktrees for isolation** — use git worktrees for parallel implementation work
- **Max 3-4 concurrent** — quality over quantity
- **Sequential phases produce files** — Research → Plan → Implement → Review → Verify

### Context Guard

- Delegate research to subagents (separate context windows)
- Keep files modular (hundreds of lines, not thousands)
- Compact proactively at ~70% context usage
- Fresh sessions per unrelated task
- Include only task-relevant context, not entire codebase docs

### Safety Boundaries

- Work on feature branches, never master directly
- Auto-approve reads; confirm destructive writes
- Run tests before AND after changes
- Never force-push, never skip hooks
- Use Docker for isolation when testing risky operations
```

- [ ] **Step 2: Verify the append**

```bash
tail -20 .claude/CLAUDE-AUTONOMOUS.md
grep -n "Self-Running Agent BKMs\|Safety Boundaries" .claude/CLAUDE-AUTONOMOUS.md
```

Expected: `Self-Running Agent BKMs` heading and `Safety Boundaries` heading both appear, with `Safety Boundaries` near the end of the file.

- [ ] **Step 3: Commit**

```bash
git add .claude/CLAUDE-AUTONOMOUS.md
git commit -m "docs: move self-running agent BKMs into CLAUDE-AUTONOMOUS.md"
```

---

## Task 4: Trim AGENTS.md

**Files:**
- Modify: `AGENTS.md`

Four edits: collapse Hybrid Tool Usage, delete AI Development Learnings, replace Self-Running BKMs with pointer, replace Production BKMs with pointer.

- [ ] **Step 1: Collapse the `Hybrid Tool Usage` section — keep only opening mandate + table**

Replace this entire block:
```
**IMPORTANT: Always call corvia MCP tools FIRST before using native tools for any
development task or question.** corvia is the project's knowledge base — skipping it
means you risk re-discovering decisions that were already made or contradicting
established patterns. This applies to ALL agents (Claude Code, Codex, etc.).

### When to use corvia MCP tools (ALWAYS do this first)

- **Starting ANY task**: Call `corvia_search` first to find prior decisions, design
  context, or patterns relevant to the work. **This is mandatory, not optional.**
- **Answering ANY question about the project**: Call `corvia_search` before searching code.
- **Understanding "why"**: Use `corvia_search` for questions about architecture, rationale,
  or past discussions (e.g., "why does LiteStore use JSON files?").
- **Recording decisions**: Use `corvia_write` to persist design decisions, architectural
  context, or implementation notes that future sessions should know.
- **Health checks**: Use `corvia_status` to verify the store is healthy before heavy work.

### When to use native tools

- **Reading/editing specific files** — corvia doesn't replace file access.
- **Searching for code patterns** — precise text/regex matching in source code.
- **Running commands** — builds, tests, git, CLI tools.
- **File discovery** — finding files by name or extension.

### Hybrid patterns

| Task | corvia first | Then native tools |
|------|-------------|-------------------|
| Start a feature | `corvia_search` for prior art/decisions | Read relevant files, implement |
| Debug an issue | `corvia_search` "how does X work?" | Search code, read files, fix |
| Explore unfamiliar area | `corvia_search` for high-level context | Search/read for code details |
| Make a design decision | `corvia_search` for existing patterns | Write design doc, `corvia_write` to record |
| Review a PR or change | `corvia_search` for relevant knowledge | Read changed files, search for impact |

### Rule of thumb

> **corvia = project knowledge & context. Native tools = source code & execution.**
> **Always check corvia first** — it's fast and prevents re-discovering things that
> were already decided. Do NOT jump straight to file reads or code search without
> checking corvia for relevant context first.
```

With:
```
**IMPORTANT: Always call corvia MCP tools FIRST before using native tools for any
development task or question.** corvia is the project's knowledge base — skipping it
means you risk re-discovering decisions that were already made or contradicting
established patterns. This applies to ALL agents (Claude Code, Codex, etc.).

### Hybrid patterns

| Task | corvia first | Then native tools |
|------|-------------|-------------------|
| Start a feature | `corvia_search` for prior art/decisions | Read relevant files, implement |
| Debug an issue | `corvia_search` "how does X work?" | Search code, read files, fix |
| Explore unfamiliar area | `corvia_search` for high-level context | Search/read for code details |
| Make a design decision | `corvia_search` for existing patterns | Write design doc, `corvia_write` to record |
| Review a PR or change | `corvia_search` for relevant knowledge | Read changed files, search for impact |
```

- [ ] **Step 2: Delete the `AI Development Learnings` section**

Remove this entire block:
```
## AI Development Learnings

Key principles applied here:
- **Context engineering > prompt engineering** — AGENTS.md is essential infrastructure
- **Verify explicitly** — give pass/fail criteria, run tests before claiming success
- **Guard context** — delegate research to subagents, compact proactively, fresh sessions per task
- **Record decisions** — use `corvia_write` to persist learnings (dogfood the product)
```

- [ ] **Step 3: Replace `Self-Running Agent BKMs` section with a pointer**

Replace this entire block (from `## Self-Running Agent BKMs` through `For the full autonomous protocol, see [CLAUDE-AUTONOMOUS.md](CLAUDE-AUTONOMOUS.md).`):
```
## Self-Running Agent BKMs

Best Known Methods for autonomous, long-running Claude Code sessions. Adapted from
[Anthropic engineering](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents),
[self-improving agents](https://addyosmani.com/blog/self-improving-agents/), and
[obra/superpowers](https://github.com/obra/superpowers).

### Session Continuity & Progress Tracking

- **Progress file**: Maintain a session log (`docs/session-logs/<date>-<task>.md`)
  with hard fails, decisions, and checkpoints. Enables context recovery across sessions.
- **Git-based state**: Commit after every logical unit of work with descriptive messages.
  Git history becomes the primary memory mechanism between sessions.
- **JSON for critical state**: Use JSON over markdown for state files that agents
  modify — models are less likely to corrupt structured data.
- **Single-feature focus**: Work on one feature/fix at a time. Complete it fully
  (implement → test → verify → commit) before moving to the next.

### Autonomous Execution Loop

```
1. Health check (build + tests pass?)
2. Read session log / progress file
3. corvia_search for relevant context
4. Pick next task (smallest unblocked item)
5. Implement with verification criteria defined upfront
6. Run tests + manual verification
7. Multi-persona review (SWE / PM / QA)
8. Commit + update session log
9. Record findings to corvia (corvia_write)
10. Repeat or hand off
```

### Multi-Persona Review Gate

Every non-trivial change is reviewed through **five** independent lenses before commit.
Three are standard; two are dynamic based on the task (see `dev-loop` skill for selection table):

**Standard (always present):**
- **Senior SWE**: Correctness, safety, idiomatic patterns, edge cases, performance
- **Product Manager**: Goal alignment, UX coherence, milestone advancement, scope
- **QA Engineer**: Test coverage, E2E verification, failure modes, regression risk

**Dynamic (task-dependent, select two):**
- Chosen based on issue labels and changed files (e.g., Security Engineer for auth work,
  Performance Engineer for optimization, UX Designer for dashboard changes)

Each reviewer MUST be a deep, independent subagent run — not a shallow one-liner.
Reviews producing less than 10 lines of substantive feedback are invalid.

### Error Recovery

- **Never retry blindly** — diagnose root cause first
- **Log every failure** in the session log with full context
- **Fix forward** — address the underlying issue, not just the symptom
- **Verify the fix** with a test that would have caught the original bug
- **Record in corvia** so future sessions don't hit the same issue

### Parallelization

- **Subagents for research** — delegate broad exploration to background agents
- **Worktrees for isolation** — use git worktrees for parallel implementation work
- **Max 3-4 concurrent** — quality over quantity
- **Sequential phases produce files** — Research → Plan → Implement → Review → Verify

### Context Guard

- Delegate research to subagents (separate context windows)
- Keep files modular (hundreds of lines, not thousands)
- Compact proactively at ~70% context usage
- Fresh sessions per unrelated task
- Include only task-relevant context, not entire codebase docs

### Safety Boundaries

- Work on feature branches, never master directly
- Auto-approve reads; confirm destructive writes
- Run tests before AND after changes
- Never force-push, never skip hooks
- Use Docker for isolation when testing risky operations

For the full autonomous protocol, see [CLAUDE-AUTONOMOUS.md](CLAUDE-AUTONOMOUS.md).
```

With:
```
For autonomous session patterns (execution loop, multi-persona review gate, error recovery, parallelization): see `.claude/CLAUDE-AUTONOMOUS.md`.
```

- [ ] **Step 4: Replace `Production Agent BKMs` section with a pointer**

Replace this entire block (from `## Production Agent BKMs` through `  → Production (guardrails, evaluation, observability) → Scaled (multi-agent, GPU, fine-tuning).`):
```
## Production Agent BKMs

Best Known Methods for building production-grade AI agents, adapted from
[agents-towards-production](https://github.com/NirDiamant/agents-towards-production).

### Architecture

- **Graph-based orchestration**: Use directed graph architectures with explicit state
  transitions for multi-step workflows. Avoid linear chains for anything non-trivial.
- **Layered separation of concerns**: Keep orchestration, memory, tools, security, and
  evaluation as distinct layers. Do not mix tool-calling logic with reasoning logic.
- **Protocol-first integration**: Adopt MCP for tool integration and A2A for multi-agent
  communication. Protocol-based design makes agents composable and replaceable.

### Memory Systems

- **Dual-memory architecture**: Short-term (session/conversation context) + long-term
  (persistent knowledge with semantic search — this is what corvia provides).
- **Self-improving memory**: Design memory that evolves through interaction — automatic
  insight extraction, conflict resolution, and knowledge consolidation across sessions.

### Security (Defense-in-Depth)

- **Three-layer guardrails**: Input validation (prompt injection prevention), behavioral
  constraints (during execution), and output filtering (before delivery to user).
- **Tool access control**: Restrict which tools an agent can invoke based on user context
  and permissions. Never give agents unrestricted access to external tools.
- **User isolation**: Prevent cross-user data leakage in multi-user deployments.

### Observability

- **Trace every decision point**: Capture the full reasoning chain — which tools were
  called, what the LLM decided, timing data for each step.
- **Instrument from day one**: Do not bolt on observability later. Traces are essential
  for debugging, performance analysis, and evaluation.
- **Monitor cost, latency, accuracy** continuously, not just during development.

### Evaluation & Testing

- **Domain-specific test suites**: Build evaluation sets tailored to your domain.
  Generic benchmarks are insufficient.
- **Multi-dimensional metrics**: Evaluate beyond accuracy — include cost per interaction,
  latency, safety compliance, and tool-use correctness.
- **Iterative improvement cycles**: Evaluation should produce actionable insights that
  feed back into agent refinement.

### Deployment Strategy

- **Containerize everything**: Docker for portability and environment consistency.
- **Start stateless, migrate to persistent**: Prototype without memory, then layer in
  persistence once the workflow is stable.
- **Production readiness progression**: Prototype → Functional (add memory, auth, tracing)
  → Production (guardrails, evaluation, observability) → Scaled (multi-agent, GPU, fine-tuning).
```

With:
```
For production agent architecture patterns (graph orchestration, memory systems, security, observability, deployment): see `docs/references/production-agent-bkms.md`.
```

- [ ] **Step 5: Verify AGENTS.md looks correct**

```bash
wc -l AGENTS.md
grep -n "When to use corvia MCP tools\|When to use native tools\|Rule of thumb\|AI Development Learnings\|Self-Running Agent BKMs\|Production Agent BKMs" AGENTS.md
grep -n "Hybrid patterns\|CLAUDE-AUTONOMOUS\|production-agent-bkms\|Hybrid Tool Usage" AGENTS.md
```

Expected: no matches for the deleted section headings; matches for the pointers and the retained table heading. Line count should be roughly 130–145 (down from 310).

- [ ] **Step 6: Commit**

```bash
git add AGENTS.md
git commit -m "docs: trim AGENTS.md — collapse hybrid usage, remove BKM sections, replace with pointers"
```

---

## Task 5: Upgrade Dev-Loop Model Files to Opus

**Files:**
- Modify: `.agents/skills/dev-loop/phases/REVIEW-DISPATCH.md`
- Modify: `.agents/skills/dev-loop/FIVE-PERSONA-REVIEWER.md`
- Modify: `.agents/skills/dev-loop/E2E-TESTER.md`

Each file has `**Model:** sonnet` on its first line. Change to `**Model:** opus`.

- [ ] **Step 1: Update REVIEW-DISPATCH.md**

Replace:
```
**Model:** sonnet
**Role:** Subagent — determine review tier, dispatch reviewers, collect results.
```

With:
```
**Model:** opus
**Role:** Subagent — determine review tier, dispatch reviewers, collect results.
```

- [ ] **Step 2: Update FIVE-PERSONA-REVIEWER.md**

Replace the first line:
```
**Model:** sonnet
```

With:
```
**Model:** opus
```

- [ ] **Step 3: Update E2E-TESTER.md**

Replace the first line:
```
**Model:** sonnet
```

With:
```
**Model:** opus
```

- [ ] **Step 4: Verify all three files**

```bash
head -1 .agents/skills/dev-loop/phases/REVIEW-DISPATCH.md
head -1 .agents/skills/dev-loop/FIVE-PERSONA-REVIEWER.md
head -1 .agents/skills/dev-loop/E2E-TESTER.md
```

Expected: all three print `**Model:** opus`.

- [ ] **Step 5: Commit**

```bash
git add .agents/skills/dev-loop/phases/REVIEW-DISPATCH.md \
        .agents/skills/dev-loop/FIVE-PERSONA-REVIEWER.md \
        .agents/skills/dev-loop/E2E-TESTER.md
git commit -m "chore: upgrade dev-loop review and E2E phases to opus"
```

---

## Task 6: Set Opus as Default Model in Global Settings

**Files:**
- Modify: `~/.claude/settings.json`

Change the global default model from sonnet to opus.

- [ ] **Step 1: Update `~/.claude/settings.json`**

The file currently contains `"model": "sonnet"`. Replace:
```json
  "model": "sonnet",
```

With:
```json
  "model": "opus",
```

- [ ] **Step 2: Verify the change**

```bash
grep '"model"' ~/.claude/settings.json
```

Expected: `"model": "opus",`

- [ ] **Step 3: Commit note**

`~/.claude/settings.json` is outside the repo — no git commit needed. The change takes effect immediately for new Claude Code sessions.

---

## Success Criteria

- [ ] `grep -n "Emergency hook bypass\|WSL memory\|Recording Decisions" CLAUDE.md` returns no matches
- [ ] `grep -n "Model Selection" CLAUDE.md` returns a match
- [ ] `grep -n "When to use corvia MCP tools\|Rule of thumb\|AI Development Learnings" AGENTS.md` returns no matches
- [ ] `grep -n "CLAUDE-AUTONOMOUS\|production-agent-bkms" AGENTS.md` returns pointer lines
- [ ] `tail -5 .claude/CLAUDE-AUTONOMOUS.md` shows Safety Boundaries bullet points
- [ ] `cat docs/references/production-agent-bkms.md | head -3` shows the file exists
- [ ] `head -1 .agents/skills/dev-loop/phases/REVIEW-DISPATCH.md` shows `**Model:** opus`
- [ ] `head -1 .agents/skills/dev-loop/FIVE-PERSONA-REVIEWER.md` shows `**Model:** opus`
- [ ] `head -1 .agents/skills/dev-loop/E2E-TESTER.md` shows `**Model:** opus`
- [ ] `grep '"model"' ~/.claude/settings.json` shows `"model": "opus"`
