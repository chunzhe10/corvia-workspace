# Context File Optimization & Model Selection Design

**Date:** 2026-04-16
**Branch:** `chore/trim-context-files`

## Goal

1. Trim CLAUDE.md and AGENTS.md to remove ~2,470 tokens of low-signal content while keeping all session-actionable guidance.
2. Add model selection guidance to CLAUDE.md.
3. Upgrade dev-loop review/E2E phases to opus for high-judgment work.
4. Set opus as the default model in settings.json.

## Principle

> If the cost of missing something exceeds the cost of a token, use opus.

## Part 1: CLAUDE.md Trims

| Section | Action | Savings |
|---------|--------|---------|
| `Emergency hook bypass` (lines 39–68) | **Delete entirely** — no `corvia hooks run` in settings.json; dead documentation | ~280 tokens |
| `WSL memory leak` (lines 74–83) | **Delete** — passive background behavior, not agent-actionable | ~80 tokens |
| `Server restart procedure` (lines 85–106) | **Compress to 2 lines** | ~130 tokens |
| `` `corvia-dev rebuild` cmake failure `` (lines 109–112) | **Compress to 1 line** | ~50 tokens |
| `corvia MCP tool usage (detailed)` (lines 20–35) | **Delete bullets, add 1-line pointer** to AGENTS.md hybrid table | ~140 tokens |
| `Recording Decisions` (lines 132–137) | **Delete** — schema already in AGENTS.md "MCP Server" section | ~60 tokens |

**CLAUDE.md additions:**

Add `## Model Selection` section (see Part 3 below).

## Part 2: AGENTS.md Trims

| Section | Action | Savings |
|---------|--------|---------|
| `Self-Running Agent BKMs` (lines 161–242) | **Move to `.claude/CLAUDE-AUTONOMOUS.md`** (append to end), replace with 1-line pointer | ~600 tokens |
| `Production Agent BKMs` (lines 244–297) | **Move to `docs/references/production-agent-bkms.md`** (new dir), replace with 1-line pointer | ~800 tokens |
| `Hybrid Tool Usage` verbosity (lines 54–94) | **Keep opening mandate + table only**; delete "When to use corvia" bullets, "When to use native tools" bullets, "Rule of thumb" callout | ~250 tokens |
| `AI Development Learnings` (lines 153–159) | **Delete entirely** — 4 principles already expressed more concretely elsewhere | ~90 tokens |

## Part 3: Model Selection Guidance (add to CLAUDE.md)

```markdown
## Model Selection

Default model: opus (set in settings.json).

| Task type | Model |
|-----------|-------|
| Info gathering, corvia lookups, quick lookups | `/model haiku` |
| Routine coding, execution, refactoring | `/model sonnet` |
| Design, review, debugging, E2E (default) | opus |
```

## Part 4: Phase 5 Implementation Subagent Models

Within `subagent-driven-development`, the orchestrator (main context = opus) dispatches subagents. Be explicit about model per role:

| Subagent role | Model | Rationale |
|---|---|---|
| Implementer (1-2 files, clear spec) | sonnet | Mechanical execution |
| Implementer (multi-file, integration) | sonnet | Still execution |
| Per-task spec reviewer | sonnet | Checklist comparison |
| Per-task code quality reviewer | **opus** | Judgment call |
| Final code reviewer (whole impl) | **opus** | Judgment call |

This is orchestrator guidance, not a file change — main context (opus) applies it at dispatch time.

## Part 5: Dev-Loop Phase File Model Upgrades

| File | Line 1 change | Rationale |
|------|--------------|-----------|
| `phases/REVIEW-DISPATCH.md` | `sonnet` → `opus` | Orchestrates all reviewer subagents — judgment phase |
| `FIVE-PERSONA-REVIEWER.md` | `sonnet` → `opus` | Last line of defense before merge |
| `E2E-TESTER.md` | `sonnet` → `opus` | Finding subtle integration bugs requires nuanced reasoning |

Unchanged: `phases/INTAKE.md` (haiku — gathering), `phases/POC.md` (sonnet — execution).

## Part 6: Global Settings

- `~/.claude/settings.json`: change `"model": "sonnet"` → `"model": "opus"`

## Part 7: Files Changed

- `CLAUDE.md`
- `AGENTS.md`
- `.claude/CLAUDE-AUTONOMOUS.md` (receives Self-Running BKMs content, appended to end)
- `docs/references/production-agent-bkms.md` (new file + new directory, receives Production BKMs content)
- `.agents/skills/dev-loop/phases/REVIEW-DISPATCH.md`
- `.agents/skills/dev-loop/FIVE-PERSONA-REVIEWER.md`
- `.agents/skills/dev-loop/E2E-TESTER.md`
- `~/.claude/settings.json`

## Part 8: Success Criteria

- CLAUDE.md + AGENTS.md total token count drops from ~5,400 to ~2,950
- All removed content is accessible via pointers or moved to appropriate files
- `**Model:** opus` appears in REVIEW-DISPATCH.md, FIVE-PERSONA-REVIEWER.md, E2E-TESTER.md
- `settings.json` defaults to opus
- Model selection table present in CLAUDE.md
