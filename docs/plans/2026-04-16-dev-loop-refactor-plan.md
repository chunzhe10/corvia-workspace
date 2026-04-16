# Dev-Loop Skill Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the dev-loop skill from a 630-line monolith into a lightweight orchestrator with per-phase files, adding POC validation, TDD, systematic debugging, scaled reviews, and pivot paths.

**Architecture:** SKILL.md becomes a ~150-line orchestrator that defines flow, gates, and pivots. Phase-specific detail moves to files under `phases/`. Subagent templates stay at the top level. All files use UPPER-KEBAB.md naming. Dispatched subagents specify a model (haiku or sonnet).

**Tech Stack:** Markdown skill files (superpowers plugin format)

**Design spec:** `docs/plans/2026-04-16-dev-loop-refactor-design.md`

---

### Task 1: Directory Structure and File Renames

**Files:**
- Create: `.agents/skills/dev-loop/phases/` (directory)
- Rename: `.agents/skills/dev-loop/five-persona-reviewer.md` → `FIVE-PERSONA-REVIEWER.md`
- Rename: `.agents/skills/dev-loop/e2e-tester.md` → `E2E-TESTER.md`

- [ ] **Step 1: Create the phases subdirectory**

Run: `mkdir -p .agents/skills/dev-loop/phases`

- [ ] **Step 2: Rename five-persona-reviewer.md to UPPER-KEBAB**

Run: `git mv .agents/skills/dev-loop/five-persona-reviewer.md .agents/skills/dev-loop/FIVE-PERSONA-REVIEWER.md`

- [ ] **Step 3: Rename e2e-tester.md to UPPER-KEBAB**

Run: `git mv .agents/skills/dev-loop/e2e-tester.md .agents/skills/dev-loop/E2E-TESTER.md`

- [ ] **Step 4: Verify structure**

Run: `find .agents/skills/dev-loop -type f -o -type d | sort`

Expected:
```
.agents/skills/dev-loop
.agents/skills/dev-loop/E2E-TESTER.md
.agents/skills/dev-loop/FIVE-PERSONA-REVIEWER.md
.agents/skills/dev-loop/ISSUE-TEMPLATE.md
.agents/skills/dev-loop/phases
.agents/skills/dev-loop/SKILL.md
```

- [ ] **Step 5: Commit**

```bash
git add .agents/skills/dev-loop/
git commit -m "chore: rename dev-loop files to UPPER-KEBAB, create phases dir"
```

---

### Task 2: Write phases/KNOWLEDGE.md

**Files:**
- Create: `.agents/skills/dev-loop/phases/KNOWLEDGE.md`

This is a reference doc (not dispatched as subagent). It documents corvia_write
patterns, field values, and commit workflow for all phases.

- [ ] **Step 1: Create the file**

Write `.agents/skills/dev-loop/phases/KNOWLEDGE.md` with this content:

```markdown
# Knowledge Store Integration

**Role:** Reference — not dispatched as subagent.

Documents how the dev-loop saves knowledge at phase boundaries. The orchestrator
references this file; subagents consult it for `corvia_write` patterns.

## When to Write

| Phase | Trigger | content_role | What to save |
|-------|---------|-------------|-------------|
| 2 (Brainstorm) | Design approved | `decision` | Key design choices and rationale |
| 4 (POC) | Spike complete | `finding` | POC results regardless of outcome |
| 5 (Implement) | Non-obvious discovery | `learning` | Patterns, gotchas, workarounds |
| 7 (Fix) | Fix loop complete | `learning` | Review insights that generalize |
| 9 (Finish) | Branch complete | `decision` | Final comprehensive decision record |

## corvia_write Patterns

### Design Decision (Phase 2, 9)

```
corvia_write:
  content_role: "decision"
  source_origin: "repo:corvia"    # or "workspace" for cross-repo decisions
  content: |
    # <Feature> — Design Decision
    ## What: <1-sentence summary>
    ## Why: <rationale, constraints, trade-offs>
    ## Alternatives rejected: <what was considered and why not>
```

### Learning (Phase 5, 7)

```
corvia_write:
  content_role: "learning"
  source_origin: "repo:corvia"
  content: "<what you discovered and why it matters for future sessions>"
```

### Finding (Phase 4)

```
corvia_write:
  content_role: "finding"
  source_origin: "repo:corvia"
  content: |
    # POC: <assumption tested>
    ## Result: CONFIRMED | INVALIDATED
    ## Evidence: <what was observed>
    ## Implication: <impact on implementation>
```

### Final Decision Record (Phase 9)

```
corvia_write:
  content_role: "decision"
  source_origin: "repo:corvia"
  content: |
    # <Feature> — Decision Record (<date>)
    ## What: <1-sentence summary>
    ## Key Design Decisions:
    1. <decision and why>
    ## Review Findings Worth Remembering:
    - <reusable insight>
    ## What Blocked / Surprised:
    - <non-obvious obstacles>
```

## The Test

> "Would a future agent session benefit from knowing this?"

If yes → `corvia_write` immediately. Don't batch until Phase 9.
If no → skip. The knowledge store is organizational memory, not a journal.

## What NOT to Save

- Code snippets (they're in git)
- Test results (they're in CI)
- Reviewer verdicts (they're in the PR)
- Anything obvious from code comments
- Temporary debugging state

## Git Commit Workflow

`corvia_write` creates JSON files in `.corvia/knowledge/` but does NOT commit
them. Include them in your regular commits:

```bash
git add .corvia/knowledge/
# Include in the next logical commit alongside code changes
```

If the knowledge store is in a separate git repo from the code, commit separately:

```bash
git add .corvia/knowledge/
git commit -m "chore: sync knowledge store (<brief description>)"
git push
```
```

- [ ] **Step 2: Commit**

```bash
git add .agents/skills/dev-loop/phases/KNOWLEDGE.md
git commit -m "feat(dev-loop): add knowledge store integration reference"
```

---

### Task 3: Write REVIEWER-PERSONAS.md

**Files:**
- Create: `.agents/skills/dev-loop/REVIEWER-PERSONAS.md`

Lookup table of detailed checklists for dynamic reviewer types. Referenced by
`phases/REVIEW-DISPATCH.md` when selecting dynamic reviewers.

- [ ] **Step 1: Create the file**

Write `.agents/skills/dev-loop/REVIEWER-PERSONAS.md` with this content:

```markdown
# Dynamic Reviewer Personas

**Role:** Reference — not dispatched as subagent.

Each persona provides the `{PERSONA_DESCRIPTION}` injected into
`FIVE-PERSONA-REVIEWER.md` when dispatching dynamic reviewers.
Used by `phases/REVIEW-DISPATCH.md` during reviewer selection.

---

## Security Engineer

Focus on:
- **Authentication/authorization**: Are access controls correct and complete?
- **Input validation**: Is user input sanitized at system boundaries?
- **Injection risks**: SQL, command, path traversal, XSS possibilities?
- **Secrets management**: Are credentials, tokens, API keys handled safely?
- **Cryptography**: Are crypto primitives used correctly? No custom crypto?
- **Error information leakage**: Do error messages expose internal details?
- **Dependency vulnerabilities**: Are new dependencies from trusted sources?

Common issues: Missing auth checks on new endpoints, overly broad permissions,
secrets in logs or error messages, TOCTOU race conditions.

---

## Performance Engineer

Focus on:
- **Algorithmic complexity**: O(n^2) where O(n) would work? Unnecessary iterations?
- **Memory allocation**: Excessive cloning, large allocations in hot paths?
- **I/O patterns**: Unbuffered I/O, N+1 queries, missing batching?
- **Caching**: Opportunities missed? Cache invalidation correct?
- **Concurrency**: Lock contention, unnecessary serialization?
- **Resource cleanup**: Handles, connections, temp files properly released?
- **Benchmarks**: Are performance-sensitive changes measured?

Common issues: Allocating in loops, holding locks across I/O, missing indexes,
unbounded collections.

---

## API Design Reviewer

Focus on:
- **Consistency**: Does the API follow existing conventions in the codebase?
- **Naming**: Are endpoints, fields, methods named clearly and predictably?
- **Versioning**: Are breaking changes handled? Migration path clear?
- **Error responses**: Are errors structured, documented, actionable?
- **Pagination**: Are list endpoints paginated? Cursor vs offset?
- **Idempotency**: Are mutating operations safe to retry?
- **Documentation**: Are new endpoints documented with examples?

Common issues: Inconsistent naming, missing pagination, undocumented error codes,
non-idempotent POST endpoints.

---

## Backwards Compatibility Reviewer

Focus on:
- **Breaking changes**: Do existing clients still work without modification?
- **Data migration**: Are existing data formats still readable?
- **Config changes**: Do new config fields have sensible defaults?
- **API stability**: Are deprecated fields still accepted? Sunset timeline?
- **Behavioral changes**: Does existing functionality behave the same way?
- **Dependency updates**: Do version bumps introduce breaking transitive changes?

Common issues: Renamed fields without aliases, removed defaults, changed
serialization format, new required config without migration.

---

## UX Designer

Focus on:
- **User flow**: Is the interaction intuitive? Minimum steps to accomplish goal?
- **Feedback**: Does the UI communicate state changes, errors, loading?
- **Consistency**: Does it match existing UI patterns in the product?
- **Accessibility basics**: Keyboard navigable? Sufficient contrast? Labels?
- **Edge states**: Empty states, error states, loading states handled?
- **Responsiveness**: Does it work at different viewport sizes?

Common issues: Missing loading indicators, inconsistent button placement,
no empty state handling, unclear error messages.

---

## Accessibility Reviewer

Focus on:
- **Semantic HTML**: Proper heading hierarchy, landmark regions, ARIA roles?
- **Keyboard navigation**: All interactive elements reachable and operable?
- **Screen reader**: Content order logical? Images have alt text? Forms labeled?
- **Color**: Sufficient contrast ratios? Information not conveyed by color alone?
- **Focus management**: Focus visible? Modals trap focus? Focus restored on close?
- **Motion**: Respects prefers-reduced-motion? No auto-playing animations?

Common issues: Missing alt text, div-based buttons without role/tabindex,
color-only status indicators, focus traps.

---

## SRE/Platform Engineer

Focus on:
- **Observability**: Are new operations logged, traced, metriced?
- **Error recovery**: Does the system degrade gracefully? Auto-recovery?
- **Configuration**: Are new settings documented? Reasonable defaults?
- **Resource limits**: Memory bounds, connection pools, queue depths set?
- **Startup/shutdown**: Clean initialization and graceful shutdown?
- **Health checks**: Do probes cover the new functionality?

Common issues: Silent failures, missing health check coverage, unbounded
queues, no graceful shutdown handling.

---

## Container/Deploy Specialist

Focus on:
- **Dockerfile**: Multi-stage build? Minimal image? No secrets in layers?
- **Dependencies**: All runtime deps included? No dev-only deps in prod?
- **Configuration**: Env vars documented? Config map structure sensible?
- **Networking**: Ports documented? Service discovery correct?
- **Storage**: Volumes mounted correctly? Permissions right?
- **Rollback**: Can this deployment be rolled back safely?

Common issues: Missing runtime dependencies, hardcoded paths, wrong
file permissions, no rollback strategy.

---

## ML Engineer

Focus on:
- **Model integration**: Are model inputs/outputs correctly shaped?
- **Preprocessing**: Is input normalization consistent with training?
- **Performance**: Batch inference where possible? GPU utilization?
- **Error handling**: What happens when inference fails? Fallback?
- **Versioning**: How are model versions tracked and switched?
- **Resource management**: Memory cleanup after inference? Session reuse?

Common issues: Shape mismatches, inconsistent normalization, missing
fallbacks, memory leaks from unreleased tensors.

---

## Data Pipeline Reviewer

Focus on:
- **Data integrity**: Are transformations correct? Edge cases handled?
- **Idempotency**: Can the pipeline be re-run safely?
- **Schema evolution**: Are schema changes backwards compatible?
- **Error handling**: What happens with malformed data? Poison messages?
- **Monitoring**: Are pipeline metrics captured? Alert on failures?
- **Backfill**: Can historical data be reprocessed?

Common issues: Non-idempotent writes, missing dead letter handling,
schema changes without migration, no backfill strategy.

---

## Rust Idiom Reviewer

Focus on:
- **Ownership patterns**: Unnecessary cloning? Borrow where possible?
- **Error handling**: Proper use of Result/Option? No unwrap in library code?
- **Trait design**: Are traits minimal and composable?
- **Iterator usage**: Collect vs lazy iteration? Unnecessary allocations?
- **Lifetime annotations**: Are they correct and minimal?
- **Clippy compliance**: Would `cargo clippy` flag anything?

Common issues: Unnecessary `.clone()`, `unwrap()` in library code,
overly broad trait bounds, `collect()` then iterate again.

---

## Unsafe/Lifetime Reviewer

Focus on:
- **Unsafe blocks**: Is each `unsafe` justified? Documented? Minimal scope?
- **Invariants**: Are safety invariants documented and maintained?
- **FFI boundaries**: Are foreign types correctly represented? Null checks?
- **Memory safety**: No use-after-free, double-free, buffer overflow?
- **Send/Sync**: Are Send/Sync implementations correct?
- **Lifetime correctness**: Do lifetimes accurately represent data dependencies?

Common issues: Overly broad unsafe blocks, missing safety comments,
incorrect Send/Sync, dangling references across FFI.

---

## Domain Expert

Focus on:
- **Domain correctness**: Does the implementation match domain semantics?
- **Business rules**: Are all business rules implemented completely?
- **Edge cases**: Are domain-specific edge cases handled?
- **Terminology**: Does the code use correct domain terminology?
- **Integration**: Does it interact correctly with other domain components?

Adapt your review to the specific domain of the changes.

---

## Developer Experience Reviewer

Focus on:
- **API ergonomics**: Is the API easy to use correctly? Hard to misuse?
- **Error messages**: Are they actionable? Do they suggest fixes?
- **Documentation**: Are public APIs documented with examples?
- **Defaults**: Are default values sensible for the common case?
- **Discoverability**: Can users find the feature? Is naming intuitive?
- **Migration**: Is the upgrade path from existing patterns clear?

Common issues: Confusing parameter ordering, non-actionable errors,
missing examples, surprising defaults.
```

- [ ] **Step 2: Commit**

```bash
git add .agents/skills/dev-loop/REVIEWER-PERSONAS.md
git commit -m "feat(dev-loop): add dynamic reviewer personas reference"
```

---

### Task 4: Write phases/INTAKE.md

**Files:**
- Create: `.agents/skills/dev-loop/phases/INTAKE.md`

Subagent template dispatched with haiku. Handles issue fetch, claim, corvia
context, and branch creation.

- [ ] **Step 1: Create the file**

Write `.agents/skills/dev-loop/phases/INTAKE.md` with this content:

```markdown
# Phase 1: Issue Intake

**Model:** haiku
**Role:** Subagent — gather all context before any code work.

## Inputs

- `{ISSUE_NUMBER}`: GitHub issue number
- `{REPO}`: Repository (default: current repo from `gh repo view --json nameWithOwner`)

## Steps

### 1.1: Fetch the GitHub Issue

```bash
gh issue view {ISSUE_NUMBER} --json title,body,labels,assignees,milestone
```

Extract:
- **Title** and **description/prompt**
- **Labels** (bug, feature, enhancement, etc.)
- **Acceptance criteria** (if present)
- **Linked issues/PRs**

### 1.2: Check Assignment

If the issue already has an assignee, STOP and report:

> "Issue #{ISSUE_NUMBER} is already assigned to {assignee}. Cannot proceed."

Do NOT claim an already-assigned issue.

### 1.3: Claim the Issue

```bash
gh issue edit {ISSUE_NUMBER} --add-assignee "@me"
gh issue edit {ISSUE_NUMBER} --add-label "in-progress"
gh issue comment {ISSUE_NUMBER} --body "Claimed by Claude Code agent — starting dev-loop."
```

### 1.4: Query Knowledge Store

```
corvia_search: "<issue title and key terms>"  scope_id: "corvia"
corvia_ask: "What prior decisions relate to <feature/area>?"  scope_id: "corvia"
```

Record what is returned — this informs brainstorming.

### 1.5: Create Feature Branch

```bash
git checkout -b <type>/<NUMBER>-<short-desc> master
```

Branch type from issue labels:
- `enhancement`, `feature` → `feat/`
- `bug` → `fix/`
- `refactor` → `refactor/`
- Default → `chore/`

## Output

Return to orchestrator:

```
ISSUE_TITLE: <title>
ISSUE_BODY: <description>
LABELS: <comma-separated>
ACCEPTANCE_CRITERIA: <extracted criteria or "none specified">
CORVIA_CONTEXT: <summary of relevant knowledge found>
BRANCH: <branch name created>
```
```

- [ ] **Step 2: Commit**

```bash
git add .agents/skills/dev-loop/phases/INTAKE.md
git commit -m "feat(dev-loop): add intake phase subagent template"
```

---

### Task 5: Write phases/POC.md

**Files:**
- Create: `.agents/skills/dev-loop/phases/POC.md`

Subagent template dispatched with sonnet. Validates `[POC]`-tagged assumptions
from the implementation plan.

- [ ] **Step 1: Create the file**

Write `.agents/skills/dev-loop/phases/POC.md` with this content:

```markdown
# Phase 4: Proof of Concept

**Model:** sonnet
**Role:** Subagent — validate assumptions tagged `[POC]` in the implementation plan.

## Inputs

- `{ASSUMPTIONS}`: List of `[POC]`-tagged assumptions from the plan
- `{DESIGN_CONTEXT}`: Relevant design decisions from Phase 2
- `{CORVIA_CONTEXT}`: Knowledge store context from Phase 1

## Process

For each `[POC]` assumption:

### 1. State the Hypothesis

Write a clear, testable statement:

```
Hypothesis: [specific claim to validate]
Pass criteria: [observable outcome that confirms]
Fail criteria: [observable outcome that invalidates]
```

### 2. Spike

Write the minimum code needed to test the hypothesis:
- Target the specific uncertainty, nothing else
- Inline exploration — spike in-place, no worktree
- Keep the spike small (< 50 lines of new code)
- Write a quick test if the hypothesis is testable via `cargo test`

### 3. Evaluate

Run the spike and observe:
- Does the outcome match pass or fail criteria?
- Any unexpected behavior or side effects?
- Performance characteristics if relevant

### 4. Clean Up

- Remove or comment out spike code (it will be reimplemented properly in Phase 5)
- Do NOT leave spike artifacts in the working tree

### 5. Save to Knowledge Store

Regardless of outcome, record the finding (see `phases/KNOWLEDGE.md`, Finding pattern):

```
corvia_write:
  content_role: "finding"
  source_origin: "repo:corvia"
  content: |
    # POC: <assumption tested>
    ## Result: CONFIRMED | INVALIDATED
    ## Evidence: <what was observed>
    ## Implication: <impact on implementation>
```

## Output

For each assumption, report:

```
ASSUMPTION: [what was tested]
RESULT: CONFIRMED | INVALIDATED | PARTIALLY CONFIRMED
EVIDENCE: [what you observed]
IMPLICATION: [what this means for the implementation plan]
```

## Outcome Rules

- **All confirmed** → return summary. Orchestrator proceeds silently to Phase 5.
- **Any invalidated** → return summary with implications. Orchestrator informs
  user and pivots to Phase 2 (Brainstorm) with findings.
- **Partially confirmed** → return summary with caveats. Orchestrator informs
  user and lets them decide: proceed with caveats or pivot.
```

- [ ] **Step 2: Commit**

```bash
git add .agents/skills/dev-loop/phases/POC.md
git commit -m "feat(dev-loop): add POC phase subagent template"
```

---

### Task 6: Write phases/REVIEW-DISPATCH.md

**Files:**
- Create: `.agents/skills/dev-loop/phases/REVIEW-DISPATCH.md`

Subagent template dispatched with sonnet. Determines review tier, dispatches
reviewers in parallel, collects results.

- [ ] **Step 1: Create the file**

Write `.agents/skills/dev-loop/phases/REVIEW-DISPATCH.md` with this content:

```markdown
# Phase 6: Review Dispatch

**Model:** sonnet
**Role:** Subagent — determine review tier, dispatch reviewers, collect results.

## Inputs

- `{BASE_SHA}`: Merge base with master (`git merge-base HEAD master`)
- `{HEAD_SHA}`: Current HEAD (`git rev-parse HEAD`)
- `{ISSUE_LABELS}`: Labels from the GitHub issue
- `{WHAT_WAS_IMPLEMENTED}`: Summary of implementation work
- `{PLAN_OR_REQUIREMENTS}`: Design/plan reference
- `{ISSUE_CONTEXT}`: Original issue description

## Step 1: Determine Review Tier

Calculate diff size:

```bash
git diff --stat {BASE_SHA}..{HEAD_SHA} | tail -1
```

Select tier:

| Diff Size | Tier | Reviewers |
|-----------|------|-----------|
| < 50 lines changed | Light | Senior SWE + QA (2) |
| 50-200 lines changed | Standard | Senior SWE + QA + PM (3) |
| 200+ lines changed | Full | Senior SWE + QA + PM + 2 dynamic (5) |

**Override:** If `{ISSUE_LABELS}` contains `review:full`, use Full tier regardless.

## Step 2: Select Dynamic Reviewers (Full Tier Only)

Match issue labels and changed files to select 2 dynamic reviewers:

| Issue Labels / Changed Files | Dynamic Persona 1 | Dynamic Persona 2 |
|------------------------------|-------------------|-------------------|
| `performance`, optimization | Performance Engineer | Storage Specialist |
| `security`, auth | Security Engineer | Compliance Reviewer |
| `api`, integration | API Design Reviewer | Backwards Compat Reviewer |
| `dashboard`, UI files | UX Designer | Accessibility Reviewer |
| `infrastructure`, devops | SRE/Platform Engineer | Container Specialist |
| `ml`, embedding | ML Engineer | Data Pipeline Reviewer |
| `rust`, unsafe code | Rust Idiom Reviewer | Unsafe/Lifetime Reviewer |
| General / unlabeled | Domain Expert | Developer Experience Reviewer |

Read the selected persona's checklist from `REVIEWER-PERSONAS.md`.

## Step 3: Dispatch Reviewers

Use `superpowers:dispatching-parallel-agents` to send all reviewers in parallel.

For each reviewer, populate the `FIVE-PERSONA-REVIEWER.md` template with:

| Placeholder | Value |
|-------------|-------|
| `{PERSONA_TITLE}` | e.g., "Senior SWE", "Security Engineer" |
| `{PERSONA_DESCRIPTION}` | Standard: from FIVE-PERSONA-REVIEWER.md inline guides. Dynamic: from REVIEWER-PERSONAS.md |
| `{WHAT_WAS_IMPLEMENTED}` | From input |
| `{PLAN_OR_REQUIREMENTS}` | From input |
| `{ISSUE_CONTEXT}` | From input |
| `{BASE_SHA}` | From input |
| `{HEAD_SHA}` | From input |

**Validation:** Each reviewer MUST return at least 10 lines of substantive
feedback. If a reviewer returns less, re-dispatch with explicit instructions
to be thorough.

## Step 4: Collect and Categorize

Aggregate all reviewer outputs. Categorize issues by severity:

| Level | Action |
|-------|--------|
| **Critical** | Blocks merge. Must fix before proceeding. |
| **Important** | Blocks merge. Must fix before proceeding. |
| **Low** | Must fix. Does not block E2E testing but blocks merge. |
| **Minor/Nitpick** | Optional. Does NOT block merge. |

## Output

Return to orchestrator:

```
REVIEW_TIER: Light | Standard | Full
REVIEWERS_DISPATCHED: <count>
REVIEWER_VERDICTS:
  - Senior SWE: Ready | Not Ready | With Fixes
  - QA Engineer: Ready | Not Ready | With Fixes
  - [PM: Ready | Not Ready | With Fixes]
  - [Dynamic 1: Ready | Not Ready | With Fixes]
  - [Dynamic 2: Ready | Not Ready | With Fixes]
ISSUES_BY_SEVERITY:
  Critical: <count>
  Important: <count>
  Low: <count>
  Minor: <count>
ISSUE_DETAILS:
  [full issue list with file:line references]
RECOMMENDATION: proceed_to_e2e | enter_fix_loop
```
```

- [ ] **Step 2: Commit**

```bash
git add .agents/skills/dev-loop/phases/REVIEW-DISPATCH.md
git commit -m "feat(dev-loop): add review dispatch phase subagent template"
```

---

### Task 7: Update FIVE-PERSONA-REVIEWER.md

**Files:**
- Modify: `.agents/skills/dev-loop/FIVE-PERSONA-REVIEWER.md` (already renamed in Task 1)

Update the dynamic reviewer section to reference `REVIEWER-PERSONAS.md` instead
of the generic one-liner. Add model selector.

- [ ] **Step 1: Add model selector and update dynamic section**

At the top of `FIVE-PERSONA-REVIEWER.md`, before the first heading, add:

```
**Model:** sonnet
```

Replace the existing dynamic reviewer section (lines 69-73 of the original):

```markdown
### If you are a Dynamic Reviewer

Focus on your domain expertise as described in your persona. Apply deep domain
knowledge that the standard three reviewers may lack. Be specific and technical.
```

With:

```markdown
### If you are a Dynamic Reviewer

Your specific focus areas and checklist are provided in `{PERSONA_DESCRIPTION}`
above, sourced from `REVIEWER-PERSONAS.md`. Follow that checklist with the same
depth and rigor as the standard reviewer guides. Apply deep domain knowledge
that the standard three reviewers may lack. Be specific and technical — generic
feedback like "consider security implications" is not acceptable.
```

- [ ] **Step 2: Commit**

```bash
git add .agents/skills/dev-loop/FIVE-PERSONA-REVIEWER.md
git commit -m "feat(dev-loop): update reviewer template for dynamic personas"
```

---

### Task 8: Update E2E-TESTER.md

**Files:**
- Modify: `.agents/skills/dev-loop/E2E-TESTER.md` (already renamed in Task 1)

Add model selector. Content stays the same.

- [ ] **Step 1: Add model selector**

At the top of `E2E-TESTER.md`, before the first heading, add:

```
**Model:** sonnet
```

- [ ] **Step 2: Commit**

```bash
git add .agents/skills/dev-loop/E2E-TESTER.md
git commit -m "chore(dev-loop): add model selector to E2E tester template"
```

---

### Task 9: Rewrite SKILL.md as Lightweight Orchestrator

**Files:**
- Rewrite: `.agents/skills/dev-loop/SKILL.md`

This is the core task. Replace the 630-line monolith with a ~150-line
orchestrator that defines flow, gates, pivots, and skill invocations.

- [ ] **Step 1: Rewrite SKILL.md**

Replace the entire contents of `.agents/skills/dev-loop/SKILL.md` with:

```markdown
---
name: dev-loop
description: Use when starting work on a GitHub issue — orchestrates the full development lifecycle from issue intake through brainstorming, planning, POC validation, TDD implementation, scaled review, debug-first fixes, E2E testing, and branch completion. Designed for autonomous multi-agent operation.
---

# Dev Loop

End-to-end autonomous development workflow: GitHub issue in, completed branch out.

**Announce at start:** "I'm using the dev-loop skill to work on issue #N."

## When to Use

- Starting work on a GitHub issue (feature, bug fix, enhancement, refactor)
- Non-trivial work that benefits from structured process

**Don't use for:** Quick typo fixes, single-line config changes, documentation-only updates.

## Pipeline

​```dot
digraph dev_loop {
    rankdir=TB;
    node [shape=box];

    intake [label="1. Intake\n(subagent: haiku)\nphases/INTAKE.md"];
    brainstorm [label="2. Brainstorm\nsuperpowers:brainstorming"];
    plan [label="3. Plan\nsuperpowers:writing-plans\ntag [POC] tasks"];
    poc [label="4. POC [conditional]\n(subagent: sonnet)\nphases/POC.md"];
    implement [label="5. Implement (TDD)\nsuperpowers:subagent-driven-development\n+ superpowers:test-driven-development"];
    review [label="6. Review (scaled)\n(subagent: sonnet)\nphases/REVIEW-DISPATCH.md"];
    fix [label="7. Fix (debug-first)\nsuperpowers:systematic-debugging\n+ superpowers:receiving-code-review"];
    e2e [label="8. E2E\n(subagent: sonnet)\nE2E-TESTER.md"];
    finish [label="9. Finish\nsuperpowers:finishing-a-development-branch"];

    intake -> brainstorm;
    brainstorm -> plan;
    plan -> poc [label="has [POC] tasks"];
    plan -> implement [label="no [POC] tasks"];
    poc -> implement [label="confirmed"];
    poc -> brainstorm [label="invalidated\n(inform user)" style=dashed];
    implement -> review;
    review -> fix [label="issues found"];
    review -> e2e [label="all clear"];
    fix -> review [label="re-review"];
    e2e -> fix [label="issues found"];
    e2e -> finish [label="pass"];

    implement -> brainstorm [label="design flaw\n(inform user)" style=dashed];
    review -> brainstorm [label="architectural issue\n(inform user)" style=dashed];
    fix -> brainstorm [label="3+ iterations\n(inform user)" style=dashed];
}
​```

## Phase Reference

| Phase | Skill / File | Dispatched as | Knowledge save |
|-------|-------------|---------------|----------------|
| 1. Intake | `phases/INTAKE.md` | Subagent (haiku) | — |
| 2. Brainstorm | `superpowers:brainstorming` | Main context | `decision` |
| 3. Plan | `superpowers:writing-plans` | Main context | — |
| 4. POC | `phases/POC.md` | Subagent (sonnet) | `finding` |
| 5. Implement | `superpowers:subagent-driven-development` + `superpowers:test-driven-development` | Main context | `learning` |
| 6. Review | `phases/REVIEW-DISPATCH.md` | Subagent (sonnet) | — |
| 7. Fix | `superpowers:systematic-debugging` + `superpowers:receiving-code-review` | Main context | `learning` |
| 8. E2E | `E2E-TESTER.md` + `superpowers:verification-before-completion` | Subagent (sonnet) | — |
| 9. Finish | `superpowers:finishing-a-development-branch` | Main context | `decision` |

For knowledge store patterns and field values, see `phases/KNOWLEDGE.md`.

## Phase Gates

| Phase | Exit condition |
|-------|----------------|
| 1 | Issue claimed, context gathered, branch created |
| 2 | Design approved by user |
| 3 | Plan reviewed; `[POC]` tasks tagged if assumptions are uncertain |
| 4 | All assumptions validated (or user informed of invalidation) |
| 5 | All tasks implemented with passing tests |
| 6 | Review verdicts collected |
| 7 | All Critical/Important/Low issues fixed |
| 8 | All E2E tests pass |
| 9 | Branch completed per user's choice (PR, merge, or cleanup) |

## Phase-Specific Notes

### Phase 3: Plan

The plan MUST tag tasks with `[POC]` when they involve unvalidated assumptions.
Examples: "does this API support streaming?", "will concurrent writes conflict?",
"is this library compatible with our MSRV?"

### Phase 4: POC (Conditional)

Only runs if the plan contains `[POC]`-tagged tasks. Dispatches a sonnet subagent
using `phases/POC.md`. Results determine next step:
- All confirmed → proceed silently to Phase 5
- Any invalidated → inform user, pivot to Phase 2 with findings
- Partially confirmed → inform user, let them decide

### Phase 5: Implement (TDD)

Each implementation subagent uses BOTH `superpowers:subagent-driven-development`
and `superpowers:test-driven-development`. The TDD cycle (red → green → refactor)
applies per task. Commit after each completed task.

### Phase 6: Review (Scaled)

Dispatches a sonnet subagent using `phases/REVIEW-DISPATCH.md` which determines
review tier by diff size:
- < 50 lines → 2 reviewers (Senior SWE + QA)
- 50-200 lines → 3 reviewers (+ PM)
- 200+ lines → 5 reviewers (+ 2 dynamic from `REVIEWER-PERSONAS.md`)

Issue label `review:full` overrides to 5 reviewers.

### Phase 7: Fix (Debug-First)

Invoke `superpowers:systematic-debugging` BEFORE attempting any fix. Root cause
first, then fix. Process review feedback with `superpowers:receiving-code-review`.
Fix by severity: Critical → Important → Low. Re-review only changed areas.
Max 3 fix-review iterations before escalating to user.

## Pivot Rules

- **Expected outcome** → proceed autonomously
- **Unexpected outcome / broken assumption** → inform user before pivoting

| Discovery | Pivot to |
|-----------|----------|
| POC invalidates assumption | Phase 2 (Brainstorm) |
| Implementation hits design flaw | Phase 3 (Plan) or Phase 2 (Brainstorm) |
| Review flags architectural issue | Phase 2 (Brainstorm) or Phase 4 (POC) |
| E2E reveals approach doesn't work | Phase 4 (POC) |
| Fix loop exceeds 3 iterations | Escalate → Phase 2 (Brainstorm) |

**Pivot protocol:**
1. Stop current phase
2. Summarize finding and proposed pivot target
3. Inform user
4. Wait for acknowledgment
5. Jump to target phase with accumulated context

## Red Flags

**STOP and reassess if:**
- Fix-review loop exceeds 3 iterations
- E2E reveals issues in unrelated areas (regression)
- Implementation diverges from approved design
- Any reviewer flags security or data-loss concern

**Never:**
- Skip Phase 2 brainstorming
- Merge without passing tests
- Force-push to any shared branch
- Proceed past a gate without meeting its criteria

## Autonomy Guidelines

1. **Proceed without asking** through Phases 1-5 if the issue is well-specified
2. **Pause and ask** if:
   - The issue is ambiguous or has conflicting requirements
   - Brainstorming produces fundamentally different approaches
   - A reviewer flags a design-level concern
3. **Always notify** the user when:
   - Phase 6 review completes (with verdicts)
   - Phase 8 E2E completes (with results)
   - Phase 9 finish completes (with PR link or merge confirmation)
```

- [ ] **Step 2: Verify line count**

Run: `wc -l .agents/skills/dev-loop/SKILL.md`
Expected: ~150-180 lines

- [ ] **Step 3: Commit**

```bash
git add .agents/skills/dev-loop/SKILL.md
git commit -m "refactor(dev-loop): rewrite SKILL.md as lightweight orchestrator"
```

---

### Task 10: Verify Cross-References

**Files:**
- Read: All files in `.agents/skills/dev-loop/`

Verify that every file reference in the dev-loop skill points to a file that
exists, and that the naming is consistent.

- [ ] **Step 1: List all files**

Run: `find .agents/skills/dev-loop -type f | sort`

Expected:
```
.agents/skills/dev-loop/E2E-TESTER.md
.agents/skills/dev-loop/FIVE-PERSONA-REVIEWER.md
.agents/skills/dev-loop/ISSUE-TEMPLATE.md
.agents/skills/dev-loop/REVIEWER-PERSONAS.md
.agents/skills/dev-loop/SKILL.md
.agents/skills/dev-loop/phases/INTAKE.md
.agents/skills/dev-loop/phases/KNOWLEDGE.md
.agents/skills/dev-loop/phases/POC.md
.agents/skills/dev-loop/phases/REVIEW-DISPATCH.md
```

- [ ] **Step 2: Check cross-references in SKILL.md**

Grep for all file references in SKILL.md and verify each exists:

Run: `grep -oP '[\w/-]+\.md' .agents/skills/dev-loop/SKILL.md | sort -u`

Expected references:
- `phases/INTAKE.md` → exists
- `phases/POC.md` → exists
- `phases/KNOWLEDGE.md` → exists
- `phases/REVIEW-DISPATCH.md` → exists
- `E2E-TESTER.md` → exists
- `REVIEWER-PERSONAS.md` → exists

- [ ] **Step 3: Check cross-references in phase files**

Run: `grep -rhoP '[\w/-]+\.md' .agents/skills/dev-loop/phases/ | sort -u`

Verify all referenced files exist.

- [ ] **Step 4: Check cross-references in REVIEW-DISPATCH.md**

Must reference:
- `FIVE-PERSONA-REVIEWER.md` → exists
- `REVIEWER-PERSONAS.md` → exists

- [ ] **Step 5: Check cross-references in FIVE-PERSONA-REVIEWER.md**

Must reference:
- `REVIEWER-PERSONAS.md` → exists

- [ ] **Step 6: Final commit (if any fixes needed)**

```bash
# Only if cross-reference fixes were needed
git add .agents/skills/dev-loop/
git commit -m "fix(dev-loop): correct cross-references between skill files"
```
