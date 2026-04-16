# Dev-Loop Skill Refactor — Design Spec

**Date:** 2026-04-16
**Status:** Draft
**Scope:** `.agents/skills/dev-loop/`

## 1. Problem

The current `SKILL.md` is a 630-line monolith that acts as both orchestrator and
detail carrier. It is missing three superpowers skills (`test-driven-development`,
`systematic-debugging`, `dispatching-parallel-agents`), has no POC validation phase,
no backtrack/pivot paths, and no review scaling. Adding these features would push
it past 800 lines, reducing LLM compliance reliability.

## 2. Solution

Split into a lightweight orchestrator SKILL.md (~150-200 lines) that owns
flow/gates/pivots, with phase-specific detail in separate files. Add a conditional
POC phase, pivot paths, TDD enforcement, debug-first fix loop, and scaled reviews.

## 3. File Structure

```
dev-loop/
├── SKILL.md                    # Orchestrator: flow, gates, pivots (~150-200 lines)
├── ISSUE-TEMPLATE.md           # Reference: how to write dev-loop issues
├── phases/
│   ├── INTAKE.md               # Subagent (haiku): fetch issue, claim, corvia context, branch
│   ├── POC.md                  # Subagent (sonnet): conditional spike to validate assumptions
│   ├── KNOWLEDGE.md            # Reference: corvia_write patterns, fields, commit workflow
│   └── REVIEW-DISPATCH.md      # Subagent (sonnet): tier selection, parallel dispatch, fix loop
├── FIVE-PERSONA-REVIEWER.md    # Subagent (sonnet): review template with placeholders
├── REVIEWER-PERSONAS.md        # Reference: detailed checklists per reviewer type
└── E2E-TESTER.md               # Subagent (sonnet): E2E test strategy and output format
```

### Naming Convention

All files use `UPPER-KEBAB.md`. `SKILL.md` stays uppercase per superpowers plugin
convention.

### Model Selectors

Files dispatched as subagents specify a recommended model to save tokens:

| File | Role | Model |
|------|------|-------|
| `SKILL.md` | Orchestrator | Inherits user's model |
| `ISSUE-TEMPLATE.md` | Reference | N/A (not dispatched) |
| `phases/INTAKE.md` | Subagent | Haiku |
| `phases/POC.md` | Subagent | Sonnet |
| `phases/KNOWLEDGE.md` | Reference | N/A (not dispatched) |
| `phases/REVIEW-DISPATCH.md` | Subagent | Sonnet |
| `FIVE-PERSONA-REVIEWER.md` | Subagent | Sonnet |
| `REVIEWER-PERSONAS.md` | Reference | N/A (not dispatched) |
| `E2E-TESTER.md` | Subagent | Sonnet |

Superpowers skills handle their own model selection dynamically. The dev-loop
does not override them.

## 4. Pipeline (9 Phases)

```
1. Intake → 2. Brainstorm → 3. Plan → 4. POC [conditional] → 5. Implement (TDD)
                ↑                            │                        │
                │                  confirms → proceed silently        │
                │                  invalidates → inform user ─────────┤
                │                                                     │
                │   6. Review (scaled) → 7. Fix (debug-first) → 8. E2E → 9. Finish
                │        │                     │                  │
                └────────┴─────────────────────┴──────────────────┘
                        pivot back on discovery (inform user first)
```

### Phase Details

#### Phase 1: Intake

- **Dispatched as:** Subagent (haiku) using `phases/INTAKE.md`
- **Actions:** Fetch issue via `gh`, claim (assign + label), query corvia for
  context, create feature branch
- **Exit gate:** Issue claimed, context gathered, branch created
- **Returns to orchestrator:** Issue title, description, labels, acceptance
  criteria, corvia context summary

#### Phase 2: Brainstorm & Design

- **Invoked as:** `superpowers:brainstorming` in main context
- **Input:** Issue context from Phase 1
- **Exit gate:** Design approved by user
- **Knowledge:** Save design decisions to corvia (see `phases/KNOWLEDGE.md`)

#### Phase 3: Implementation Plan

- **Invoked as:** `superpowers:writing-plans` in main context
- **Input:** Approved design from Phase 2
- **Key requirement:** Plan MUST tag tasks with `[POC]` when they involve
  unvalidated assumptions (e.g., "does this API support streaming?",
  "will concurrent writes conflict?")
- **Exit gate:** Plan reviewed

#### Phase 4: POC (Conditional)

- **Condition:** Only runs if the plan contains `[POC]`-tagged tasks
- **Dispatched as:** Subagent (sonnet) using `phases/POC.md`
- **Approach:** Inline exploration — spike code in-place, no worktree
- **Outcomes:**
  - Assumption confirmed → proceed silently to Phase 5
  - Assumption invalidated or unexpected result → inform user, then pivot
    back to Phase 2 (brainstorm) with findings
- **Knowledge:** Save POC findings to corvia regardless of outcome

#### Phase 5: Implementation (TDD)

- **Invoked as:** `superpowers:subagent-driven-development` in main context
- **TDD enforcement:** Each implementation subagent task also uses
  `superpowers:test-driven-development` — red/green/refactor per task
- **Commit cadence:** Commit after each completed task
- **Knowledge:** Save non-obvious patterns and gotchas to corvia

#### Phase 6: Review (Scaled)

- **Dispatched as:** Subagent (sonnet) using `phases/REVIEW-DISPATCH.md`
- **Review tiers by diff size:**
  - < 50 lines changed → 2 reviewers (Senior SWE + QA)
  - 50–200 lines changed → 3 reviewers (Senior SWE + QA + PM)
  - 200+ lines changed → 5 reviewers (Senior SWE + QA + PM + 2 dynamic)
- **Override:** Issue label `review:full` forces 5 reviewers regardless of size
- **Dispatch method:** Uses `superpowers:dispatching-parallel-agents` to send
  all reviewers in parallel
- **Templates:** `FIVE-PERSONA-REVIEWER.md` for structure,
  `REVIEWER-PERSONAS.md` for dynamic reviewer checklists
- **Output:** Collected review verdicts and issues by severity

#### Phase 7: Fix (Debug-First)

- **Invoked as:** `superpowers:systematic-debugging` then
  `superpowers:receiving-code-review` in main context
- **Process:** Root cause investigation before any fix attempt
- **Fix order:** Critical → Important → Low
- **Re-review:** Only re-review changed areas after fixes
- **Loop limit:** Max 3 iterations, then escalate to user
- **Knowledge:** Save review insights to corvia

#### Phase 8: E2E Integration Testing

- **Dispatched as:** Subagent (sonnet) using `E2E-TESTER.md`
- **Verification:** Also invoke `superpowers:verification-before-completion`
  before claiming E2E pass
- **Scope:** Happy path + edge cases + regression + full test suite
- **On failure:** Loop back to Phase 7 (fix) with E2E findings

#### Phase 9: Finish

- **Invoked as:** `superpowers:finishing-a-development-branch` in main context
- **Actions:** Presents structured options (merge, PR, cleanup) — user decides
- **Knowledge:** Final decision record via `phases/KNOWLEDGE.md`, commit
  knowledge JSON to workspace repo

## 5. Pivot Paths

Any phase can trigger a pivot back to an earlier phase. The orchestrator
follows these rules:

### Pivot Authority

- **Same result / expected outcome** → agent proceeds autonomously
- **Changed result / broken assumption** → inform user before pivoting

### Pivot Targets

| Discovery | Pivot to | Rationale |
|-----------|----------|-----------|
| POC invalidates assumption | Phase 2 (Brainstorm) | Fundamental rethink needed |
| Implementation hits design flaw | Phase 3 (Plan) or Phase 2 (Brainstorm) | Revise plan or rethink approach |
| Review flags architectural issue | Phase 2 (Brainstorm) or Phase 4 (POC) | Rethink if fundamental; POC if testable |
| E2E reveals approach doesn't work | Phase 4 (POC) | Test alternative approach |
| Fix loop exceeds 3 iterations | Phase 2 (Brainstorm) | Something is structurally wrong |

### Pivot Protocol

1. Stop current phase
2. Summarize what was discovered and why a pivot is needed
3. Inform user with the finding and proposed pivot target
4. Wait for user acknowledgment
5. Jump to the target phase with accumulated context

## 6. Corvia Integration

The orchestrator references corvia at phase boundaries with a one-liner:
"Save [type] to knowledge store (see `phases/KNOWLEDGE.md`)."

`phases/KNOWLEDGE.md` contains:
- `corvia_write` field mappings (`content_role`, `source_origin`)
- Examples for each phase (design decisions, learnings, findings, decision records)
- Git commit workflow for `.corvia/knowledge/` files
- The "would a future agent benefit?" test for what to save vs. skip

Phases that write to corvia: 2, 4, 5, 7, 9.

## 7. Review System

### FIVE-PERSONA-REVIEWER.md

Stays as-is structurally — a subagent prompt template with `{PLACEHOLDER}`
variables. The three standard persona guides (Senior SWE, PM, QA) remain inline.
The dynamic reviewer section changes from a single generic sentence to:
"See `REVIEWER-PERSONAS.md` for your detailed review checklist."

### REVIEWER-PERSONAS.md (New)

A lookup table mapping each dynamic reviewer type to:
- Focus areas (5-8 bullet points)
- Domain-specific checklist items
- Common issues to watch for

Dynamic reviewer types covered:
- Security Engineer
- Performance Engineer
- API Design Reviewer
- Backwards Compatibility Reviewer
- UX Designer
- Accessibility Reviewer
- SRE/Platform Engineer
- Container/Deploy Specialist
- ML Engineer
- Data Pipeline Reviewer
- Rust Idiom Reviewer
- Unsafe/Lifetime Reviewer
- Domain Expert
- Developer Experience Reviewer

### E2E-TESTER.md

Stays as-is. Already well-structured with test categories, output format,
and verdict.

## 8. ISSUE-TEMPLATE.md

Stays in the dev-loop directory as a reference companion. It helps users write
issues structured for the dev-loop pipeline. Not dispatched as a subagent.

## 9. What Gets Removed From Current SKILL.md

| Content | Approx Lines | Destination |
|---------|-------------|-------------|
| Phase 1 detail (gh commands, claim logic) | ~50 | `phases/INTAKE.md` |
| corvia_write examples + field values | ~80 | `phases/KNOWLEDGE.md` |
| 5-persona dispatch instructions | ~70 | `phases/REVIEW-DISPATCH.md` |
| Fix loop detail | ~40 | Replaced by `superpowers:systematic-debugging` |
| Phase 7 merge/conflict resolution | ~50 | Replaced by `superpowers:finishing-a-development-branch` |
| Common mistakes + red flags | ~60 | Trimmed to ~15 lines of essentials |
| Knowledge persistence table | ~30 | `phases/KNOWLEDGE.md` |

## 10. Migration

1. Write new files (`phases/INTAKE.md`, `phases/POC.md`, `phases/KNOWLEDGE.md`,
   `phases/REVIEW-DISPATCH.md`, `REVIEWER-PERSONAS.md`)
2. Rewrite `SKILL.md` as lightweight orchestrator
3. Update `FIVE-PERSONA-REVIEWER.md` dynamic section to reference `REVIEWER-PERSONAS.md`
4. Rename `e2e-tester.md` → `E2E-TESTER.md`, `five-persona-reviewer.md` → `FIVE-PERSONA-REVIEWER.md`
5. Verify all cross-references between files are correct
6. Test by dry-running the orchestrator mentally against a sample issue
