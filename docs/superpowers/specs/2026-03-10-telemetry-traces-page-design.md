# Telemetry Traces Page — Design Spec

**Date:** 2026-03-10
**Status:** Approved
**Depends on:** M4 observability (spans), dashboard redesign (view tabs)
**Affects:** `.devcontainer/extensions/corvia-services/extension.js`, `tools/corvia-dev/`

---

## Overview

Add an interactive telemetry map as the "Traces" view tab in the Corvia VS Code dashboard. Visualizes the 7 instrumented kernel modules as a node-graph topology with three rendering modes: Map (static topology), Data Flow (animated data movement), and Heat (load-derived intensity). A persistent detail panel shows span timings, mini-stats, and recent events for the selected module.

---

## Architecture

### Page Structure
- Replaces the current "Traces" placeholder in the view tab system
- Uses the existing 70/30 workspace layout but replaces log panel + sidebar with graph panel + detail panel
- Graph panel (left, flex: 1) contains mode switcher + canvas
- Detail panel (right, 280px) contains 3 stacked cards

### Rendering Modes
1. **Map** — static node-graph topology. Nodes display live stats. Click to inspect.
2. **Data Flow** — same topology with animated dots flowing along edges showing data movement direction and volume.
3. **Heat** — same topology with nodes pulsing/glowing based on derived load (span frequency, queue depth, error rate).

### Data Source
- Primary: `corvia-dev status --json` extended with a `traces` field containing span timing aggregates and recent events
- Module mapping done client-side using span name prefixes (`corvia.entry.*` → Entry, etc.)
- Span-derived heat metrics now; real resource metrics (CPU/RAM/GPU/disk) as a follow-up

### Code Structure
- All rendering in `extension.js` (existing single-file pattern)
- Graph uses absolute-positioned divs for nodes, inline SVG for edges
- Fixed layout grid for node positions (deterministic, no force-directed physics)
- No external libraries

---

## Module Topology

7 modules with fixed connections:

| Module | Color | Spans | Connects To |
|--------|-------|-------|-------------|
| Agent | peach | `agent.register`, `session.create`, `session.commit` | Entry, GC |
| Entry | gold | `entry.write`, `entry.embed`, `entry.insert` | Storage, Merge, Inference |
| Merge | mint | `merge.process`, `merge.process_entry`, `merge.conflict`, `merge.llm_resolve` | Storage |
| Storage | lavender | `store.insert`, `store.search`, `store.get` | RAG |
| RAG | mint | `rag.context`, `rag.ask` | (terminal) |
| Inference | coral | `entry.embed` (called by Entry) | (called by Entry) |
| GC | amber | `gc.run` | Storage |

Span name → module mapping prefix table:
```
corvia.agent.* → Agent
corvia.session.* → Agent
corvia.entry.* → Entry
corvia.merge.* → Merge
corvia.store.* → Storage
corvia.rag.* → RAG
corvia.gc.* → GC
```
Inference is identified by `corvia.entry.embed` context (gRPC/Ollama).

---

## Components

### Graph Panel

**Mode Switcher:**
- Segmented control (same style as log filter bar): Map / Data Flow / Heat
- Active mode: gold text + gold-soft background
- Positioned in graph toolbar alongside "Click a module to inspect" hint

**Canvas:**
- Relative-positioned container with two layers:
  - SVG edge layer (`pointer-events: none`) — curved connection lines between modules
  - Node layer — absolutely-positioned module nodes on fixed layout grid

**Module Nodes:**
Each node contains:
- Color-coded icon (32px, radius-sm, accent-soft background)
- Uppercase label in module accent color
- Stat line: key metric + span count (text-dim)
- Mini activity bar (3px, width proportional to span frequency relative to most active module)

Node states:
- Default: `bg-card` + `border`
- Hover: `bg-card-hover` + `border-bright`
- Selected: border becomes module color + `0 0 0 3px {color}-soft` outer ring

**SVG Edges:**
- Curved paths (`C` bezier) connecting module centers
- Stroke: `border` color, 1.5px
- Data Flow mode: animated dots (r=3) travel along paths via CSS `offset-path` + `offset-distance`
- Dot color matches source node's accent
- Animation speed scales inversely with activity volume

**Heat Mode Overlay:**
- Nodes get pulsing border-glow whose intensity maps to derived load
- Cool (low): mint glow
- Warm (moderate): gold glow
- Hot (high/errors): coral glow
- Mini activity bar color also reflects heat level

### Detail Panel (right 280px)

Three stacked cards, updating reactively on node selection:

**1. Module Summary:**
- Header: color dot (10px) + module name (13px/700) + description
- 2x2 mini-stat grid:
  - Total count
  - Last hour count
  - Avg latency (ms)
  - Error count
- Mini-stat style: bg-input rounded container, 18px/800 value, 9px uppercase label

**2. Instrumented Spans:**
- List of span rows with bottom borders
- Each row: mono span name (11px), field names below (10px, text-dim)
- Right-aligned timing pill (rounded, 11px mono):
  - Fast (< 50ms): mint text, mint-soft background
  - Medium (50–150ms): peach text, peach-soft background
  - Slow (> 150ms): coral text, coral-soft background

**3. Recent Events:**
- Last 10 structured log events for the selected module
- Each row: level dot (6px: mint=info, amber=warn, coral=error) + message + timestamp
- Scrollable if overflow

**Empty State:**
When no node is selected: centered text "Select a module to inspect its telemetry" (text-dim)

---

## Data Contract

### New `traces` field in status JSON

```json
{
  "traces": {
    "spans": {
      "corvia.entry.write": { "count": 24, "avg_ms": 12, "last_ms": 8, "errors": 0 },
      "corvia.entry.embed": { "count": 24, "avg_ms": 84, "last_ms": 92, "errors": 0 },
      "corvia.entry.insert": { "count": 24, "avg_ms": 8, "last_ms": 6, "errors": 0 },
      "corvia.merge.process": { "count": 5, "avg_ms": 340, "last_ms": 290, "errors": 0 },
      "corvia.store.insert": { "count": 48, "avg_ms": 15, "last_ms": 12, "errors": 0 },
      "corvia.store.search": { "count": 30, "avg_ms": 22, "last_ms": 18, "errors": 0 },
      "corvia.rag.ask": { "count": 8, "avg_ms": 1200, "last_ms": 980, "errors": 0 }
    },
    "recent_events": [
      { "ts": "14:31:52", "level": "info", "module": "entry", "msg": "Entry inserted scope:corvia" },
      { "ts": "14:30:18", "level": "warn", "module": "entry", "msg": "Slow embed: 210ms" }
    ]
  }
}
```

### Parsing Strategy
- corvia-dev CLI parses JSON-formatted tracing output from service logs
- Aggregates span timings over a rolling window
- Collects last N structured events per module
- Returns in status JSON under `traces` key

### Graceful Degradation
- If `traces` field is absent (older corvia-dev): nodes show "—" for stats, detail panel shows "Upgrade corvia-dev for span data"
- Topology map always renders regardless of data availability

---

## Design Tokens

No new colors. Reuses existing warm charcoal palette. Module-to-color mapping:
- Agent → peach (`#ffb07c`)
- Entry → gold (`#f0c94c`)
- Merge → mint (`#5eead4`)
- Storage → lavender (`#c4b5fd`)
- RAG → mint (`#5eead4`)
- Inference → coral (`#ff8a80`)
- GC → amber (`#fcd34d`)

### Timing Pill Thresholds
| Range | Color | Background |
|-------|-------|------------|
| < 50ms | mint | mint-soft |
| 50–150ms | peach | peach-soft |
| > 150ms | coral | coral-soft |

### Transitions
- All node hover/select: `0.25s cubic-bezier(0.4, 0, 0.2, 1)`
- Data Flow dots: CSS `offset-distance` animation, duration inversely proportional to activity
- Heat glow: CSS `box-shadow` animation, 2s ease-in-out infinite

---

## Responsive Behavior

Below 700px:
- Graph panel and detail panel stack vertically (single column)
- Graph panel gets min-height: 50vh
- Node positions scale proportionally via percentage-based layout

---

## What Does NOT Change
- Extension activation logic, polling interval (3s), status bar item
- Header, metrics row, view tab structure
- Logs and Graph tab content
- `onDidReceiveMessage` handler patterns
- `package.json` manifest

---

## Verification Criteria
1. Traces tab activates and renders the module topology graph
2. All 7 modules render as clickable nodes with correct colors
3. SVG edges connect modules according to the topology table
4. Mode switcher toggles between Map, Data Flow, and Heat
5. Data Flow mode shows animated dots along edges
6. Heat mode shows intensity-based glow on nodes
7. Clicking a node populates the detail panel with module summary, spans, and events
8. Span timing pills use correct color thresholds
9. Empty state shows when no node is selected
10. Graceful degradation when `traces` field is missing from status JSON
11. Layout collapses to single column below 700px
12. All transitions and hover states follow existing design token conventions

---

*Mockup reference: `/tmp/brainstorm/telemetry-map-layout-v2.html`*
*Created: 2026-03-10*
