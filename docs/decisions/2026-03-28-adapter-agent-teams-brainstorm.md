# corvia-adapter-agent-teams: Brainstorm Results

**Date:** 2026-03-28
**Status:** Brainstorm complete + spike verified, pre-RFC
**Updated:** 2026-03-28 (post-spike corrections applied)

---

## How Agent Teams Work (Verified via Spike)

**Spawning:** Lead uses Agent tool to spawn teammates as in-process subagents.
Teammates can be spawned at any time during the team's lifetime (not just at
creation). Multiple teammates spawned "simultaneously" are actually sequential
(~1-2s apart in our test).

**CORRECTION:** Teammates get NO team-specific env vars. Only `CLAUDECODE=1`,
`CLAUDE_CODE_ENTRYPOINT=cli`, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. The
`CLAUDE_CODE_TEAM_NAME` reported in external articles is NOT an env var. It exists
only in internal AsyncLocalStorage (JavaScript runtime context, not shell env).

**Teammate transcripts** are stored as subagent JSONL files under the lead's
session directory:
```
~/.claude/projects/{project}/{leadSessionId}/subagents/agent-{agentId}.jsonl
```

**File formats (verified):**

```
~/.claude/teams/{team-name}/
  config.json          # Full schema below
  inboxes/
    {agent-name}.json      # JSON array of messages
    {agent-name}.json.lock # Lock directory (not file)

~/.claude/tasks/{team-name}/
  {task-id}.json       # {id, subject, description, status, blocks, blockedBy}
  .lock                # flock() for task claiming race prevention
```

**config.json verified schema:**
```json
{
  "name": "team-name",
  "description": "...",
  "createdAt": 1774672217745,
  "leadAgentId": "team-lead@team-name",
  "leadSessionId": "658150a6-...",
  "members": [
    {
      "agentId": "team-lead@team-name",
      "name": "team-lead",
      "agentType": "team-lead",
      "model": "claude-opus-4-6[1m]",
      "joinedAt": 1774672217745,
      "tmuxPaneId": "",
      "cwd": "/workspaces/corvia-workspace",
      "subscriptions": []
    },
    {
      "agentId": "researcher@team-name",
      "name": "researcher",
      "model": "haiku",
      "prompt": "full spawn prompt here...",
      "color": "blue",
      "planModeRequired": false,
      "joinedAt": 1774672260425,
      "tmuxPaneId": "in-process",
      "cwd": "/workspaces/corvia-workspace",
      "subscriptions": [],
      "backendType": "in-process"
    }
  ]
}
```

Key: `agentId` = `{name}@{team-name}` (deterministic, not UUID).
`leadSessionId` bridges team config to lead's session history.
Teammate `prompt` is stored in full.

**Inbox message schema (verified):**
```json
[
  {
    "from": "agent-name",
    "text": "plain text or JSON-in-JSON for system messages",
    "summary": "optional short preview",
    "timestamp": "2026-03-28T04:31:06.736Z",
    "color": "blue",
    "read": true
  }
]
```

**Message types:** `task_assignment`, `message`, `broadcast`, `shutdown_request`,
`shutdown_response`, `plan_approval_request`, `plan_approval_response`, `idle_notification`

**Hook payloads (verified):**

TeammateIdle stdin:
```json
{
  "session_id": "lead-session-id",
  "transcript_path": "lead-transcript-path",
  "hook_event_name": "TeammateIdle",
  "teammate_name": "researcher",
  "team_name": "my-team"
}
```

TaskCreated stdin:
```json
{
  "session_id": "lead-session-id",
  "hook_event_name": "TaskCreated",
  "task_id": "1",
  "task_subject": "...",
  "task_description": "..."
}
```

Note: All hook `session_id` values are the LEAD's session ID, not the teammate's.

**Hooks:** `TaskCreated`, `TaskCompleted`, `TeammateIdle`. Stdin JSON includes
`session_id`, `transcript_path`, `teammate_name`, `team_name`, `task_id`, etc.

**Cleanup:** Deletes both directories entirely. Requires all teammates shut down first.

---

## Q1: Capturing Before Cleanup Deletes Files

**Recommendation: Hook-based incremental capture (primary) + periodic scan (fallback).**

Six approaches were evaluated:

| Approach | Reliability | Complexity | Verdict |
|----------|------------|------------|---------|
| Pre-cleanup hook interception | Low | High | Not viable. No native hook exists. |
| Filesystem watcher (inotify) | High | Medium-High | Works but breaks adapter model (requires persistent server process). |
| Periodic scan (polling) | Low-Medium | Low | Data loss window. OK as fallback only. |
| **Hook-based incremental** | **High** | **Medium** | **Recommended primary.** Matches claude-sessions pattern. |
| Shadow copy (hard links) | Medium | Medium | Breaks on write-via-rename (common in Node/Electron). |
| MCP-level interception | Medium | Low | Depends on agent compliance. Supplementary only. |

**How the recommended approach works:**

| Hook | Action | Latency |
|------|--------|---------|
| `TaskCreated` | Log task ID, subject, description to staging JSONL | < 50ms |
| `TaskCompleted` | Read full task file, log to staging with completion timestamp | < 100ms |
| Teammate `SessionEnd` | Read inbox, team config, remaining tasks. Final snapshot. | < 2s |

**Key invariant:** `TeammateIdle` fires before cleanup becomes possible. The shutdown
sequence is always: all teammates go idle/shut down, THEN cleanup can run. So teammate
`SessionEnd` hooks capture everything before deletion.

**Staging directory:** `~/.corvia/staging/agent-teams/{team-name}/` survives cleanup.
Adapter reads from staging, not from ephemeral team directories.

**Skip `TeammateIdle` for capture.** It fires every LLM turn (too noisy). Reserve
for quality gates, not data capture.

---

## Q2: Agent ID to Session ID Correlation (RESOLVED by spike)

**CORRECTION:** The original brainstorm assumed we needed env vars or mapping files.
The spike proved a simpler approach exists.

**Spike findings that change everything:**
1. `agentId` = `{name}@{team-name}` (deterministic, not UUID)
2. `leadSessionId` is stored in config.json (bridges team to lead's session)
3. Teammates are stored as subagent transcripts at
   `{leadSessionId}/subagents/agent-{id}.jsonl`
4. Teammate processes have NO team-specific env vars (no `CLAUDE_CODE_TEAM_NAME`,
   no `CLAUDE_CODE_AGENT_NAME`)
5. `TeammateIdle` hook gives `teammate_name` + `team_name` on stdin
6. Teammates can be spawned at any time (dynamic membership)

**Verified identity chain (no env vars needed):**

```
config.json                          Hook payloads
  leadSessionId ─────────────────→ session_id (in all hooks)
  members[].name ─────────────────→ teammate_name (in TeammateIdle)
  members[].agentId ({name}@{team}) → deterministic, reconstructable

Lead transcript
  teamName field on entries ──────→ identifies team context
  Agent tool calls ───────────────→ {name, team_name} per teammate
  subagents/ directory ───────────→ teammate transcript files
```

**No mapping file needed. No CorrelationIndex needed.** The identity is fully
determined by:
- Reading config.json (team structure, leadSessionId)
- Reading TeammateIdle hook payloads (teammate_name, team_name)
- Reading lead's transcript subagents/ directory (teammate transcripts)

**Remaining verification needed:** Test the identity chain with edge cases:
- Late-joining teammates (spawned mid-session)
- Teammates that spawn subagents (3-level hierarchy)
- Teammates that crash (no graceful shutdown)
- Sequential teams (clean up, recreate in same lead session)

---

## Q3: Incremental Capture Feasibility

**Recommendation: Hybrid (incremental hooks + batch at SessionEnd). Skip TeammateIdle.**

**What hooks provide on stdin:**

- `TaskCompleted`: task_id, subject, description, teammate_name, team_name, session_id,
  transcript_path. Can also read the full task JSON file from disk.
- `TeammateIdle`: teammate_name, team_name, session_id, transcript_path.
- `TaskCreated`: task fields from stdin.

**Critical finding:** All file reads must happen synchronously inside the hook, not
deferred. By the time an async post-processing job runs, files may be deleted.

**Why skip TeammateIdle for capture:** Fires after every LLM turn. 50 turns = 50
hook invocations with deduplication overhead. The same data is captured at teammate
`SessionEnd` in a single pass.

**Timing guarantee:** Teammate `SessionEnd` fires before lead can run cleanup. Lead's
`SessionEnd` fires after cleanup (files gone). So: teammate hooks are safe, lead
hooks are not.

---

## Q4: Message Volume and Chunking

**Recommendation: Task-grouped chunking (primary) + optional LLM extraction (secondary).**

Five approaches evaluated:

| Approach | Search quality | Storage cost | Faithfulness | Verdict |
|----------|---------------|-------------|-------------|---------|
| One entry per message | High | **Too high** (HNSW pollution) | Perfect | Reject. Same reason session adapter rejected per-event. |
| One entry per thread (sender-recipient) | Medium | Moderate | Moderate | Mediocre. Grouping axis wrong (who vs. what). |
| **One entry per task** | **High** | **Low-moderate** | **Good** | **Recommended.** Semantic boundaries = chunking boundaries. |
| One entry per team | Low | Minimal | Poor | Reject. Too diluted. |
| LLM summarization | Potentially highest | Low | Depends | Powerful as secondary layer. |

**Task-grouped chunking rules:**
- Each `task_assignment` starts a new group
- Messages referencing that task (by reply chain or task_id) join the group
- System messages (shutdown, idle) go to "session-meta" group
- Groups exceeding 512 tokens split with 64-token overlap (kernel default)
- Broadcasts attributed to originating task context

**Optional LLM extraction pass:** After structural ingestion, an async pass extracts
decisions, findings, disagreements as separate high-signal entries. Uses existing
`.classify-queue` infrastructure. Produces 3-10 entries per session.

**Entry count estimate (5-agent, 30-min session):**
- Primary: 5-15 task-group entries
- Secondary: 3-10 extracted entries
- Total: 8-25 entries per session
- 6-month steady state: ~1,500-4,500 entries

---

## Q5: Nested Subagent Attribution

**Recommendation: Rely on existing `parent_session_id` chain. No team metadata on
subagents. No direct team-to-subagent edges. Strictly hierarchical graph.**

**Graph structure (no shortcuts):**

```
team ──has_member─���> teammate session
team ──has_task────> task
task ──assigned_to─> teammate session
task ──depends_on──> task
subagent ──spawned_by──> teammate session   (already exists from claude-sessions adapter)
```

**Full traversal for "all subagent work in a team":**
```
team ──has_member──> teammate ──<spawned_by── subagent
```
Three hops. Within existing `max_depth: 3` default.

**Why no direct team->subagent edges:**
- Redundant (path exists through teammate)
- Graph pollution (O(teammates * subagents) extra edges)
- Semantically wrong (team does not know about subagents)

**Why no team metadata on subagent entries:**
- Clean layering (session data knows nothing about team coordination)
- Avoids staleness if team structure changes
- Defer denormalization until query latency is measured

**Compatibility:** The claude-sessions adapter needs zero modifications. The teams
adapter adds `has_member` edges on top of existing session entries. The `spawned_by`
edges are reused as-is.

---

## Research Spike: COMPLETED (2026-03-28)

Spike created a real Agent Teams session (`spike-env-capture`) with 2 Haiku
teammates, captured env vars and all file formats via hooks.

**Answers:**
1. `CLAUDE_CODE_AGENT_NAME` is NOT exposed as an env var. No team-specific env vars.
2. `agentId` = `{name}@{team-name}` (deterministic). Not related to session ID.
3. `leadSessionId` is in config.json. Teammate session IDs are not stored anywhere
   in team files, but teammates exist as subagent transcripts under the lead's
   session directory.

**Identity chain verified.** No mapping files or env vars needed. The combination
of config.json + TeammateIdle hook payloads + lead transcript subagents/ directory
gives full teammate identification.

**Remaining:** Verify identity mechanism with edge cases (see next section).

---

## Identity Mechanism Verification (TODO)

The identity chain must be tested with these edge cases to ensure robustness:

### Test 1: Late-joining teammate
- Create team with 1 teammate
- Let it work for a bit
- Spawn a 2nd teammate mid-session
- Verify: config.json updated, new member in subagents/, TeammateIdle fires for new member

### Test 2: Teammate spawns subagents
- Create team with 1 teammate
- Teammate spawns a subagent for research
- Verify: subagent transcript nested under teammate's transcript (or lead's?)
- Verify: graph chain team -> teammate -> subagent is reconstructable

### Test 3: Teammate crash (no graceful shutdown)
- Create team, spawn teammate
- Force-kill the teammate process
- Verify: what state remains? Does TeammateIdle fire? Is transcript preserved?

### Test 4: Sequential teams
- Create team A, do work, clean up
- Create team B in same lead session
- Verify: team A staging data survives, team B gets new config, no identity confusion

---

## Summary: Key Decisions (Post-Spike)

| Question | Decision | Confidence |
|----------|----------|-----------|
| Capture timing | Hook-based incremental + scan fallback | High |
| Identity correlation | config.json + TeammateIdle hooks + lead transcript subagents/ | **High** (spike verified) |
| Incremental vs. batch | Hybrid. Hooks during lifetime, SessionEnd final sweep. | High |
| Message chunking | Task-grouped primary, LLM extraction secondary | High |
| Subagent attribution | Existing `spawned_by` chain, no team metadata on subagents | High |
| Teammate env vars | NONE available. Do not depend on them. | **Verified** |
| agentId format | `{name}@{team-name}` (deterministic) | **Verified** |
| Dynamic membership | Teammates can join at any time | **Verified** |
