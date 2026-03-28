# corvia-adapter-agent-teams: Design Exploration

**Date:** 2026-03-28
**Status:** Exploration (not yet RFC)

---

## 1. What This Is

A corvia adapter that ingests Claude Code Agent Teams artifacts into persistent,
searchable organizational memory. When a team shuts down, its coordination state
(tasks, messages, decisions, findings) would otherwise be deleted. This adapter
captures it before cleanup.

## 2. Data Sources

Agent Teams store state in two directories:

```
~/.claude/teams/{team-name}/
  config.json                    # Team members, roles, agent IDs, agent types
  inboxes/{agent-name}.json      # Mailbox messages (JSON arrays)

~/.claude/tasks/{team-name}/
  {task-id}.json                 # Individual tasks with status, owner, deps
```

All of this is deleted when the lead runs cleanup.

### What Each Source Contains

**config.json** -- Team structure:
- Team name, creation timestamp
- Members array: name, agent_id, agent_type (lead vs teammate)
- Display mode, permission settings

**inboxes/{agent-name}.json** -- Inter-agent messages:
- Sender, recipient, timestamp
- Message content (findings, questions, status updates, plan approvals)
- Message type (direct, broadcast, shutdown request)

**tasks/{task-id}.json** -- Task coordination:
- Task description, status (pending/in_progress/completed)
- Owner (which teammate claimed it)
- Dependencies (which tasks must complete first)
- Creation/completion timestamps

## 3. Relationship to corvia-adapter-claude-sessions

The session history adapter (RFC 2026-03-14) captures individual session content
(prompts, tool calls, responses). The agent-teams adapter captures coordination
artifacts (who worked on what, what they told each other, task flow).

They are complementary, not overlapping:

| Concern | claude-sessions adapter | agent-teams adapter |
|---------|------------------------|---------------------|
| What | Session content (turns) | Coordination state |
| Granularity | Per-turn, per-session | Per-team, per-task |
| Source files | `~/.claude/sessions/*.jsonl.gz` | `~/.claude/teams/`, `~/.claude/tasks/` |
| Scope | `user-history` (personal) | `user-history` (with promotion) |
| Lifecycle | Captured at session end | Captured before team cleanup |
| Graph edges | subagent -> parent session | teammate -> team, task -> teammate, task -> task (deps) |

**Combined, they give full observability**: the sessions adapter shows what each
teammate did (tool calls, reasoning). The teams adapter shows how they coordinated
(task flow, messages, decisions).

### Graph Integration

The agent-teams adapter should create edges that connect to session history entries:

```
team:security-review
  ├── has_member → session:ses-abc123 (lead)
  ├── has_member → session:ses-def456 (security reviewer)
  ├── has_member → session:ses-ghi789 (perf reviewer)
  ├── has_task → task:review-auth-module
  │     ├── assigned_to → session:ses-def456
  │     └── depends_on → task:setup-test-fixtures
  └── has_task → task:review-perf-impact
        └── assigned_to → session:ses-ghi789
```

This requires correlating `agent_id` from team config with `session_id` from
session logs. The link is the Claude Code agent ID that both systems share.

## 4. Adapter Architecture

Follows the D75 JSONL protocol (same as git, basic, claude-sessions adapters).

### Binary

`corvia-adapter-agent-teams` -- standalone binary in `adapters/corvia-adapter-agent-teams/rust/`

### Metadata

```json
{
  "name": "agent-teams",
  "version": "0.1.0",
  "domain": "agent-teams",
  "protocol_version": 1,
  "description": "Claude Code Agent Teams coordination history",
  "supported_extensions": ["json"],
  "chunking_extensions": []
}
```

No custom chunking needed. Team artifacts are small enough to ingest as-is.

### Ingestion Flow

```
1. Scan ~/.claude/teams/ for team directories
2. For each team:
   a. Read config.json -> one SourceFile (team structure entry)
   b. Read tasks/*.json -> one SourceFile per task
   c. Read inboxes/*.json -> one SourceFile per message thread
   d. Check .ingested state file to skip already-processed teams
3. Return Vec<SourceFile> via JSONL
4. Kernel embeds and stores
5. Wire graph edges (team -> members, tasks -> owners, task deps)
```

### SourceMetadata Mapping

| Field | Value |
|-------|-------|
| `scope_id` | `"user-history"` (same as session history) |
| `content_role` | `"memory"` for team config, `"finding"` for messages, `"plan"` for tasks |
| `source_origin` | `"claude:team:{team-name}"` |
| `source_version` | `"{team-name}:{artifact-type}:{id}"` |
| `workstream` | Git branch from lead's spawn context (if available) |

### Trigger Mechanism

Two options:

**Option A: Hook-based (preferred)**
Hook into the `TeammateIdle` event to capture task completions incrementally.
Hook into team cleanup (no native hook exists -- would need to watch for file
deletion or wrap the cleanup command).

**Option B: Periodic scan**
Run `corvia workspace ingest` on a schedule. The adapter scans for teams that
exist but haven't been ingested yet. Simpler but risks missing teams that get
cleaned up between scans.

**Option C: Hybrid**
Hooks capture incrementally during team lifetime. A scan pass at ingest time
catches anything hooks missed. This matches how claude-sessions works
(hooks capture events, adapter processes at session end).

## 5. Knowledge Entries Produced

### Team Structure Entry

```
[Team: security-review | Created: 2026-03-28T10:00:00Z]
LEAD: main-agent (agent-id: abc123)
TEAMMATES:
  - security-reviewer (agent-id: def456)
  - perf-reviewer (agent-id: ghi789)
  - test-validator (agent-id: jkl012)
PURPOSE: Review PR #142 from security, performance, and test coverage angles
```

### Task Entry

```
[Task: review-auth-module | Team: security-review | Status: completed]
DESCRIPTION: Review authentication module for security vulnerabilities.
  Focus on token handling, session management, input validation.
ASSIGNED TO: security-reviewer
DEPENDS ON: setup-test-fixtures
CREATED: 2026-03-28T10:01:00Z
COMPLETED: 2026-03-28T10:15:00Z
```

### Message Thread Entry

```
[Messages: security-reviewer <-> perf-reviewer | Team: security-review]
[10:05] security-reviewer -> perf-reviewer:
  "Found that the JWT validation skips expiry check on refresh tokens.
   Does the refresh endpoint have rate limiting?"
[10:07] perf-reviewer -> security-reviewer:
  "No rate limiting on /api/refresh. The endpoint also doesn't log
   failed attempts. Flagging both as high severity."
[10:08] security-reviewer -> broadcast:
  "Consensus: refresh token handling needs a rewrite. See findings doc."
```

## 6. Query Patterns Enabled

Once ingested, users and agents can ask:

- "What did the security review team find last week?"
- "Which teammates worked on the auth refactor?"
- "What tasks were assigned to the performance reviewer?"
- "Show me the messages where teammates disagreed"
- "What teams have reviewed this module before?"
- "How long did the parallel investigation take vs estimated?"

Temporal queries work too: "What did we know about auth security before vs after
the team review?" shows knowledge evolution.

## 7. Promotion to Product Scope

Like claude-sessions, agent-teams entries start in `user-history`. A classification
pass identifies product-relevant findings for promotion to the `corvia` scope:

**Auto-promote** (high confidence):
- Messages containing design decisions or consensus statements
- Tasks whose descriptions reference product features or bugs
- Team findings that match patterns in existing product knowledge

**Queue for review** (ambiguous):
- General discussion messages
- Debugging threads (might be product-relevant or session-specific)

## 8. Implementation Sizing

| Component | Effort | Notes |
|-----------|--------|-------|
| Adapter binary (scan + parse + emit) | Small | ~300 lines, straightforward JSON parsing |
| Graph edge wiring | Medium | Correlating agent IDs across teams and sessions |
| Hook integration (TeammateIdle, cleanup) | Medium | Depends on Agent Teams hook stability |
| Classification rules for promotion | Small | Reuse claude-sessions patterns |
| Tests | Small | Mock team directories, verify entries + edges |

Total: roughly the same size as corvia-adapter-claude-sessions. Could be built as
an extension of that adapter (same binary, different domain mode) or as a standalone.

## 9. Build vs. Extend Decision

**Option A: Standalone adapter** (`corvia-adapter-agent-teams`)
- Clean separation of concerns
- Independent release cycle
- Easier to test in isolation

**Option B: Extend claude-sessions adapter** (add `--domain agent-teams` mode)
- Shared code for JSON parsing, state tracking, graph wiring
- Single binary to discover and maintain
- Agent Teams are inherently Claude Code sessions, just coordinated

**Recommendation:** Start as Option B (extend claude-sessions). The data sources
are closely related, the graph edges need to cross-reference session IDs, and the
promotion logic is identical. If it gets too complex, split later.

## 10. Open Questions

1. **File watching vs. scan**: Agent Teams files are deleted on cleanup. Do we need
   to watch for file creation in real-time, or is hooking into cleanup sufficient?

2. **Agent ID correlation**: How reliably can we match `agent_id` from team config
   to `session_id` from session logs? Need to verify the env var chain.

3. **Incremental capture**: Can we capture task completions as they happen (via
   `TaskCompleted` hook), or only at team shutdown?

4. **Message volume**: For large teams with many broadcasts, message threads could
   be substantial. Need a chunking strategy or summarization pass?

5. **Nested subagents**: Teammates can spawn subagents. How do we attribute subagent
   findings to the correct teammate and team?

## 11. Strategic Value

This adapter is a **distribution play**:

- Every Claude Code user with Agent Teams gets immediate value from corvia
- "Your teams forget everything when they shut down. corvia remembers."
- The adapter is lightweight (small binary, no config) but creates deep adoption
- Once teams depend on corvia for cross-team memory, switching cost is high

It's also a **defensive play**:

- If Anthropic adds native team memory, corvia is already the established layer
- corvia's advantages (multi-tool, temporal, graph, git-as-truth) still apply
- Being first matters more than being perfect
