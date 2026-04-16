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
