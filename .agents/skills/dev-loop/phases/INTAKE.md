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
