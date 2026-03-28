# Spoke Dashboard Integration Design

**Date:** 2026-03-28
**Status:** Design Complete (review fixes incorporated 2026-03-28)
**Depends on:** Spoke CLI Design (2026-03-28)
**Scope:** corvia-server (dashboard routes), corvia-dashboard (React frontend)

---

## Overview

Extend the existing dashboard to show spoke containers alongside agents. The goal
is a single pane of glass where the owner sees all spokes, their status, their
current work, and their knowledge contributions.

**Design principle:** Spokes are a specialization of agents, not a separate concept.
The dashboard should integrate spoke data into the existing agent and activity views,
not create a parallel silo.

---

## Approach: Enhance AgentsView, Don't Create SpokesView

Instead of a separate "Spokes" tab, enrich the existing Agents tab with spoke
metadata. Rationale:

- Every spoke registers as a corvia agent via MCP. It already appears in AgentsView.
- A separate tab creates a navigation split. The owner would have to check two places.
- Spokes are agents with extra metadata (container, issue, branch). Show that metadata
  inline on the agent card.

The Agents tab becomes the **command center** for all agents, whether they're
interactive sessions, background adapters, or spoke containers.

---

## Backend Changes

### New endpoint: `GET /api/dashboard/spokes`

Returns Docker container metadata for all spoke containers. Merged with agent
registry data on the frontend.

```rust
// In dashboard/mod.rs
.route("/api/dashboard/spokes", get(spokes_handler))

async fn spokes_handler(
    State(state): State<Arc<AppState>>,
) -> Json<SpokesResponse> {
    // Docker client cached in AppState (initialized once at server startup)
    let Some(docker) = &state.docker else {
        return Json(SpokesResponse {
            spokes: vec![],
            warning: Some("Docker not connected".into()),
        });
    };

    let filters = HashMap::from([
        ("label".into(), vec!["corvia.spoke=true".into()]),
    ]);
    let containers = match docker.list_containers(Some(options)).await {
        Ok(c) => c,
        Err(e) => return Json(SpokesResponse {
            spokes: vec![],
            warning: Some(format!("Docker unavailable: {}", e)),
        }),
    };

    let spokes: Vec<SpokeInfo> = containers.iter().map(|c| SpokeInfo {
        name: extract_label(c, "corvia.spoke.name"),
        agent_id: format!("spoke-{}", extract_label(c, "corvia.issue")),
        repo: extract_label(c, "corvia.repo"),
        branch: extract_label(c, "corvia.branch"),
        issue: extract_label(c, "corvia.issue"),
        container_state: c.state.clone().unwrap_or_default(),
        container_status: c.status.clone().unwrap_or_default(),
        created: c.created.unwrap_or(0),
        health: extract_health(c),
    }).collect();

    Ok(Json(spokes))
}
```

### Response type

```rust
#[derive(Serialize)]
pub struct SpokeInfo {
    pub name: String,               // From Docker container name
    pub agent_id: String,           // From label corvia.agent_id
    pub repo: String,
    pub branch: String,
    pub issue: String,
    pub container_state: String,    // "running", "exited", "created"
    pub container_status: String,   // "Up 2 hours", "Exited (0) 5 min ago"
    pub created: i64,               // Unix timestamp
    pub health: String,             // "healthy", "unhealthy", "starting", "none"
    pub repo_url: Option<String>,   // For constructing issue links
}

#[derive(Serialize)]
pub struct SpokesResponse {
    pub spokes: Vec<SpokeInfo>,
    pub warning: Option<String>,    // Set when Docker unavailable
}
```

**AppState extension:**
```rust
pub struct AppState {
    // ... existing fields
    pub docker: Option<Docker>,  // Cached, initialized once at server startup
}
```

### Enhanced agents endpoint

No changes needed. Spokes auto-register as agents via MCP. The existing
`GET /api/dashboard/agents` already returns them. The frontend merges spoke
container metadata with agent records by matching `agent_id`.

### System status enhancement

Add spoke count to `GET /api/dashboard/status`:

```rust
// In status_handler, add:
"spoke_count": spokes.len(),
"spokes_running": spokes.iter().filter(|s| s.container_state == "running").count(),
```

---

## Frontend Changes

### Types (`types.ts`)

```typescript
export interface SpokeInfo {
    name: string;
    agent_id: string;
    repo: string;
    branch: string;
    issue: string;
    container_state: string;
    container_status: string;
    created: number;
    health: string;
}

// Extend AgentRecord with optional spoke data
export interface EnrichedAgent extends AgentRecord {
    spoke?: SpokeInfo;
}
```

### API (`api.ts`)

```typescript
export async function fetchSpokes(): Promise<SpokeInfo[]> {
    return get<SpokeInfo[]>("/api/dashboard/spokes");
}
```

### AgentsView Enhancement

The AgentsView already shows agents in a card grid. Enhance it:

#### 1. Merge spoke data with agent data

```typescript
function AgentsView() {
    const agents = usePoll(fetchAgents, 5000);
    const spokes = usePoll(fetchSpokes, 15000); // 15s: container state changes slowly

    // Merge: attach spoke metadata to matching agents
    const enriched: EnrichedAgent[] = useMemo(() => {
        const spokeMap = new Map(spokes.map(s => [s.agent_id, s]));
        return agents.map(a => ({
            ...a,
            spoke: spokeMap.get(a.agent_id),
        }));
    }, [agents, spokes]);

    // Sort: spokes first (active work), then other agents
    const sorted = useMemo(() =>
        [...enriched].sort((a, b) => {
            if (a.spoke && !b.spoke) return -1;
            if (!a.spoke && b.spoke) return 1;
            return 0;
        }),
    [enriched]);
}
```

#### 2. AgentCard spoke badge

When an agent has spoke metadata, show it on the card:

```typescript
function AgentCard({ agent }: { agent: EnrichedAgent }) {
    return (
        <div className="agent-card">
            {/* Existing header */}
            <div className="agent-header">
                <HeartbeatDot status={agent.status} />
                <span className="agent-name">{agent.display_name}</span>
                {agent.spoke && (
                    <span className="spoke-badge">
                        spoke
                    </span>
                )}
            </div>

            {/* Spoke-specific info */}
            {agent.spoke && (
                <div className="spoke-info">
                    <div className="spoke-row">
                        <span className="label">Issue</span>
                        <a href={issueUrl(agent.spoke.repo_url, agent.spoke.issue)}
                           target="_blank">
                            #{agent.spoke.issue}
                        </a>
                    </div>
                    <div className="spoke-row">
                        <span className="label">Branch</span>
                        <code>{agent.spoke.branch}</code>
                    </div>
                    <div className="spoke-row">
                        <span className="label">Container</span>
                        <ContainerStatus
                            state={agent.spoke.container_state}
                            health={agent.spoke.health}
                            status={agent.spoke.container_status}
                        />
                    </div>
                </div>
            )}

            {/* Existing: topic pills, stats, expandable section */}
        </div>
    );
}
```

#### 3. ContainerStatus component

```typescript
function ContainerStatus({ state, health, status }: {
    state: string;
    health: string;
    status: string;
}) {
    const color = state === "running"
        ? (health === "healthy" ? "green" : health === "unhealthy" ? "red" : "yellow")
        : "gray";

    return (
        <span className={`container-status ${color}`}>
            <span className="dot" />
            {status}
        </span>
    );
}
```

#### 4. Spokes summary bar

Add a summary bar at the top of AgentsView (similar to LiveSessionsBar):

```typescript
function SpokesSummaryBar({ spokes }: { spokes: SpokeInfo[] }) {
    const running = spokes.filter(s => s.container_state === "running").length;
    const exited = spokes.filter(s => s.container_state === "exited").length;

    if (spokes.length === 0) return null;

    return (
        <div className="spokes-summary-bar">
            <span className="spokes-count">
                {running} spoke{running !== 1 ? "s" : ""} running
            </span>
            {exited > 0 && (
                <span className="spokes-exited">
                    {exited} exited
                </span>
            )}
            <div className="spoke-pills">
                {spokes.filter(s => s.container_state === "running").map(s => (
                    <span key={s.name} className="spoke-pill" title={s.branch}>
                        #{s.issue}
                    </span>
                ))}
            </div>
        </div>
    );
}
```

### Header status enhancement

In `Layout.tsx`, the header shows service health pills. Add spoke count:

```typescript
// In header, after service pills:
{spokeCount > 0 && (
    <span className="header-spoke-count" title="Active spokes">
        {spokeCount} spokes
    </span>
)}
```

---

## Activity Feed Enhancement

The activity feed (`GET /api/dashboard/activity`) already shows knowledge entries
grouped by semantic similarity. Spoke entries naturally appear because spokes
write via `corvia_write`. No backend changes needed.

Enhancement: show the spoke badge next to entries from spoke agents:

```typescript
// In ActivityFeed entry rendering:
{/* Use spokeMap lookup, not string prefix (robust to naming changes) */}
{spokeMap.has(entry.agent_id) && (
    <span className="spoke-tag">spoke</span>
)}
```

---

## Cross-Spoke Timeline

The activity feed already provides a chronological, semantically-grouped view of
all knowledge entries. With spoke badges, this becomes the cross-spoke timeline
naturally.

For a more focused view, add a filter:

```typescript
// Activity feed filter options:
<select onChange={e => setAgentFilter(e.target.value)}>
    <option value="">All agents</option>
    {agents.filter(a => a.spoke).map(a => (
        <option key={a.agent_id} value={a.agent_id}>
            {a.spoke.name} (#{a.spoke.issue})
        </option>
    ))}
</select>
```

The backend already supports agent_id filtering on the activity endpoint
(or it can be added as a query parameter).

---

## System Status Page Enhancement

The status page (`GET /api/dashboard/status`) currently shows:
- Service health (corvia-server, corvia-inference)
- Entry count, agent count, merge queue depth

Add spoke section:

```typescript
// In status display:
<div className="status-section">
    <h3>Spokes</h3>
    <div className="status-grid">
        <StatusItem label="Running" value={status.spokes_running} />
        <StatusItem label="Total" value={status.spoke_count} />
    </div>
</div>
```

---

## Implementation Plan

### Backend (corvia-server)

| Task | File | Description |
|------|------|-------------|
| 1 | `dashboard/mod.rs` | Add `GET /api/dashboard/spokes` route and handler |
| 2 | `dashboard/mod.rs` | Add `SpokeInfo` response type |
| 3 | `dashboard/mod.rs` | Add spoke count to status handler |
| 4 | Cargo.toml | Add `bollard` dependency to corvia-server (or re-export from kernel) |

### Frontend (corvia-dashboard)

| Task | File | Description |
|------|------|-------------|
| 5 | `types.ts` | Add `SpokeInfo`, `EnrichedAgent` types |
| 6 | `api.ts` | Add `fetchSpokes()` |
| 7 | `AgentsView.tsx` | Merge spoke data, add spoke badge and info to AgentCard |
| 8 | `AgentsView.tsx` | Add SpokesSummaryBar component |
| 9 | `AgentsView.tsx` | Add ContainerStatus component |
| 10 | `Layout.tsx` | Add spoke count to header |
| 11 | `AgentsView.tsx` or `HistoryView.tsx` | Add spoke badge to activity entries |
| 12 | `AgentsView.tsx` | Add agent filter to activity/timeline |

### Estimated effort

- Backend: 4 tasks, small scope (Docker query + JSON response)
- Frontend: 8 tasks, moderate scope (component enhancements, not new pages)
- No new tabs, no new pages, no new navigation concepts

---

## What This Looks Like

```
┌─────────────────────────────────────────────────────────┐
│ corvia dashboard     [server: healthy] [inference: healthy] │
│                                              3 spokes    │
├─────────────────────────────────────────────────────────┤
│ [Traces] [Agents] [RAG] [Tiers] [Logs] [Graph] [History]│
├─────────────────────────────────────────────────────────┤
│                                                         │
│  3 spokes running                    #42  #55  #61      │
│                                                         │
│  ┌─────────────────────┐  ┌─────────────────────┐      │
│  │ spoke-42       spoke │  │ spoke-55       spoke │      │
│  │ ● Active             │  │ ● Active             │      │
│  │                      │  │                      │      │
│  │ Issue:  #42          │  │ Issue:  #55          │      │
│  │ Branch: feat/42-bm25 │  │ Branch: feat/55-viz  │      │
│  │ Container: healthy   │  │ Container: healthy   │      │
│  │ Up 2 hours           │  │ Up 45 minutes        │      │
│  │                      │  │                      │      │
│  │ Topics: search, bm25 │  │ Topics: graph, viz   │      │
│  │ Entries: 12          │  │ Entries: 7           │      │
│  │ ▼ Sessions           │  │ ▼ Sessions           │      │
│  └─────────────────────┘  └─────────────────────┘      │
│                                                         │
│  ┌─────────────────────┐  ┌─────────────────────┐      │
│  │ spoke-61       spoke │  │ claude-code          │      │
│  │ ● Active             │  │ ● Active             │      │
│  │ Issue:  #61          │  │ (interactive session) │      │
│  │ Branch: feat/61-auth │  │ Topics: design, spoke│      │
│  │ Container: healthy   │  │ Entries: 45          │      │
│  │ Up 20 minutes        │  │                      │      │
│  └─────────────────────┘  └─────────────────────┘      │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## Utilities

```typescript
// Derive issue URL from repo remote URL
function issueUrl(repoUrl: string | undefined, issue: string): string {
    if (!repoUrl) return "#";
    const match = repoUrl.match(/github\.com[:/]([^/]+\/[^/.]+)/);
    if (match) return `https://github.com/${match[1]}/issues/${issue}`;
    return "#";
}
```

Frontend shows banner when Docker is unavailable:
```typescript
{spokes.warning && (
    <div className="warning-banner">{spokes.warning}</div>
)}
```

## Observability (via corvia-telemetry)

Spoke container metrics (CPU%, memory) and lifecycle events are emitted as
OTel spans/metrics through `corvia-telemetry`, not as separate dashboard
endpoints. The Traces and Logs tabs already render these. Phase 2 may add
a dedicated metrics panel to the AgentsView if needed.

## Non-Goals

- No spoke management from the dashboard (create/destroy). That's the CLI's job.
- No log streaming in the dashboard. Use `corvia workspace spoke logs` for that.
- No separate "Spokes" tab. Spokes are agents with extra metadata.
- No real-time WebSocket updates. Polling at 15s is sufficient for spoke status.
