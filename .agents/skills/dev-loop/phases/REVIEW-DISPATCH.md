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
