# Knowledge Store Integration

**Role:** Reference — not dispatched as subagent.

Documents how the dev-loop saves knowledge to corvia at phase boundaries. The orchestrator
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
