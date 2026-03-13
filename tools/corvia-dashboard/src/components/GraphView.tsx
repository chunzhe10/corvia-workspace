import { useCallback, useEffect, useRef, useState } from "preact/hooks";
import { usePoll } from "../hooks/use-poll";
import { fetchGraphScope } from "../api";
import type { GraphNode, GraphScopeEdge, GraphScopeResponse } from "../types";

// --- Force simulation types ---

interface SimNode {
  id: string;
  label: string;
  x: number;
  y: number;
  vx: number;
  vy: number;
  pinned: boolean;
}

interface SimEdge {
  from: string;
  to: string;
  relation: string;
  weight?: number;
}

// --- Relation color palette (matches theme) ---

const RELATION_COLORS: Record<string, string> = {
  imports: "#7dd3fc",       // sky
  depends_on: "#c4b5fd",   // lavender
  implements: "#5eead4",   // mint
  supersedes: "#f0c94c",   // gold
  relates_to: "#ffb07c",   // peach
  contradicts: "#ff8a80",  // coral
  tests: "#fcd34d",        // amber
  documents: "#7dd3fc",    // sky
};

function relationColor(rel: string): string {
  return RELATION_COLORS[rel] ?? "#8a8279"; // text-dim fallback
}

// --- Force simulation ---

const SPRING_LENGTH = 120;
const SPRING_K = 0.005;
const REPULSION = 8000;
const DAMPING = 0.85;
const DT = 1;
const MIN_VELOCITY = 0.01;

function initNodes(nodes: GraphNode[], width: number, height: number): SimNode[] {
  const cx = width / 2;
  const cy = height / 2;
  const radius = Math.min(width, height) * 0.3;
  return nodes.map((n, i) => {
    const angle = (2 * Math.PI * i) / nodes.length;
    return {
      id: n.id,
      label: n.label,
      x: cx + radius * Math.cos(angle) + (Math.random() - 0.5) * 20,
      y: cy + radius * Math.sin(angle) + (Math.random() - 0.5) * 20,
      vx: 0,
      vy: 0,
      pinned: false,
    };
  });
}

function stepSimulation(nodes: SimNode[], edges: SimEdge[]): boolean {
  const nodeMap = new Map<string, SimNode>();
  for (const n of nodes) nodeMap.set(n.id, n);

  // Reset forces
  for (const n of nodes) {
    if (n.pinned) continue;
    let fx = 0;
    let fy = 0;

    // Repulsion from all other nodes
    for (const m of nodes) {
      if (m.id === n.id) continue;
      const dx = n.x - m.x;
      const dy = n.y - m.y;
      const distSq = dx * dx + dy * dy + 1;
      const f = REPULSION / distSq;
      const dist = Math.sqrt(distSq);
      fx += (f * dx) / dist;
      fy += (f * dy) / dist;
    }

    // Spring attraction along edges
    for (const e of edges) {
      let other: SimNode | undefined;
      if (e.from === n.id) other = nodeMap.get(e.to);
      else if (e.to === n.id) other = nodeMap.get(e.from);
      if (!other) continue;
      const dx = other.x - n.x;
      const dy = other.y - n.y;
      const dist = Math.sqrt(dx * dx + dy * dy) + 0.1;
      const displacement = dist - SPRING_LENGTH;
      fx += SPRING_K * displacement * (dx / dist);
      fy += SPRING_K * displacement * (dy / dist);
    }

    n.vx = (n.vx + fx * DT) * DAMPING;
    n.vy = (n.vy + fy * DT) * DAMPING;
    n.x += n.vx * DT;
    n.y += n.vy * DT;
  }

  // Check if settled
  let maxV = 0;
  for (const n of nodes) {
    const v = Math.abs(n.vx) + Math.abs(n.vy);
    if (v > maxV) maxV = v;
  }
  return maxV > MIN_VELOCITY;
}

// --- Canvas rendering ---

const NODE_RADIUS = 18;

function drawGraph(
  ctx: CanvasRenderingContext2D,
  nodes: SimNode[],
  edges: SimEdge[],
  selectedId: string | null,
  zoom: number,
  panX: number,
  panY: number,
  width: number,
  height: number,
) {
  ctx.save();
  ctx.clearRect(0, 0, width, height);

  // Background
  ctx.fillStyle = "#1e2230"; // bg-card
  ctx.fillRect(0, 0, width, height);

  ctx.translate(panX, panY);
  ctx.scale(zoom, zoom);

  const nodeMap = new Map<string, SimNode>();
  for (const n of nodes) nodeMap.set(n.id, n);

  // Draw edges
  for (const e of edges) {
    const from = nodeMap.get(e.from);
    const to = nodeMap.get(e.to);
    if (!from || !to) continue;

    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    ctx.lineTo(to.x, to.y);
    ctx.strokeStyle = relationColor(e.relation);
    ctx.globalAlpha = 0.4;
    ctx.lineWidth = 1.5 / zoom;
    ctx.stroke();
    ctx.globalAlpha = 1;

    // Edge label at midpoint
    const mx = (from.x + to.x) / 2;
    const my = (from.y + to.y) / 2;
    ctx.font = `${10 / zoom}px Inter, sans-serif`;
    ctx.fillStyle = "#8a8279"; // text-dim
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(e.relation, mx, my - 6 / zoom);
  }

  // Draw nodes
  for (const n of nodes) {
    const isSelected = n.id === selectedId;

    // Circle
    ctx.beginPath();
    ctx.arc(n.x, n.y, NODE_RADIUS / zoom, 0, 2 * Math.PI);
    ctx.fillStyle = isSelected ? "#252a3a" : "#282d3e"; // bg-card-hover / bg-input
    ctx.fill();
    ctx.strokeStyle = isSelected ? "#f0c94c" : "#504b44"; // gold / border
    ctx.lineWidth = (isSelected ? 2.5 : 1.2) / zoom;
    ctx.stroke();

    // Label (truncated)
    const label = n.label.length > 20 ? n.label.slice(0, 18) + "\u2026" : n.label;
    ctx.font = `${11 / zoom}px Inter, sans-serif`;
    ctx.fillStyle = isSelected ? "#ffffff" : "#e0ddd8"; // text-bright / text-primary
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(label, n.x, n.y + NODE_RADIUS / zoom + 12 / zoom);

    // Short ID inside circle
    const shortId = n.id.slice(0, 6);
    ctx.font = `${9 / zoom}px 'Cascadia Code', monospace`;
    ctx.fillStyle = "#b0a99f"; // text-muted
    ctx.fillText(shortId, n.x, n.y);
  }

  ctx.restore();
}

// --- Hit test ---

function hitTest(
  nodes: SimNode[],
  canvasX: number,
  canvasY: number,
  zoom: number,
  panX: number,
  panY: number,
): SimNode | null {
  const worldX = (canvasX - panX) / zoom;
  const worldY = (canvasY - panY) / zoom;
  const r = NODE_RADIUS / zoom;
  for (let i = nodes.length - 1; i >= 0; i--) {
    const n = nodes[i];
    const dx = worldX - n.x;
    const dy = worldY - n.y;
    if (dx * dx + dy * dy <= r * r * 1.5) return n;
  }
  return null;
}

// --- Component ---

const MAX_EDGES_FOR_GRAPH = 500;

export function GraphView() {
  const fetcher = useCallback(() => fetchGraphScope(), []);
  const { data, error, loading } = usePoll(fetcher, 10000);

  const canvasRef = useRef<HTMLCanvasElement>(null);
  const nodesRef = useRef<SimNode[]>([]);
  const edgesRef = useRef<SimEdge[]>([]);
  const animRef = useRef<number>(0);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const zoomRef = useRef(1);
  const panRef = useRef({ x: 0, y: 0 });
  const dragRef = useRef<{ node: SimNode; offsetX: number; offsetY: number } | null>(null);
  const panDragRef = useRef<{ startX: number; startY: number; panX: number; panY: number } | null>(null);
  const sizeRef = useRef({ w: 800, h: 600 });
  const dataIdRef = useRef("");
  const [, forceRender] = useState(0);

  // Initialize simulation when data changes
  useEffect(() => {
    if (!data) return;
    const resp = data as GraphScopeResponse;
    if (!resp.nodes || !resp.edges) return;

    // Build a stable identity for this data set
    const dataId = resp.nodes.map((n) => n.id).sort().join(",");
    if (dataId === dataIdRef.current) return; // same nodes, skip re-init
    dataIdRef.current = dataId;

    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.parentElement?.getBoundingClientRect();
    const w = rect?.width ?? 800;
    const h = rect?.height ?? 600;
    sizeRef.current = { w, h };
    canvas.width = w * devicePixelRatio;
    canvas.height = h * devicePixelRatio;
    canvas.style.width = `${w}px`;
    canvas.style.height = `${h}px`;

    nodesRef.current = initNodes(resp.nodes, w, h);
    edgesRef.current = resp.edges.map((e) => ({
      from: e.from,
      to: e.to,
      relation: e.relation,
      weight: e.weight,
    }));

    zoomRef.current = 1;
    panRef.current = { x: 0, y: 0 };
    setSelectedId(null);
  }, [data]);

  // Animation loop
  useEffect(() => {
    let running = true;
    let settled = 0;

    function tick() {
      if (!running) return;
      const canvas = canvasRef.current;
      if (!canvas) {
        animRef.current = requestAnimationFrame(tick);
        return;
      }
      const ctx = canvas.getContext("2d");
      if (!ctx) return;

      const nodes = nodesRef.current;
      const edges = edgesRef.current;

      if (nodes.length > 0) {
        const moving = stepSimulation(nodes, edges);
        if (moving) settled = 0;
        else settled++;
      }

      const dpr = devicePixelRatio;
      ctx.save();
      ctx.scale(dpr, dpr);
      drawGraph(
        ctx,
        nodes,
        edges,
        selectedId,
        zoomRef.current,
        panRef.current.x,
        panRef.current.y,
        sizeRef.current.w,
        sizeRef.current.h,
      );
      ctx.restore();

      // Keep animating if simulation is active or being dragged
      if (settled < 120 || dragRef.current) {
        animRef.current = requestAnimationFrame(tick);
      } else {
        // Slow poll for redraws
        animRef.current = window.setTimeout(() => {
          if (running) animRef.current = requestAnimationFrame(tick);
        }, 200) as unknown as number;
      }
    }

    animRef.current = requestAnimationFrame(tick);
    return () => {
      running = false;
      cancelAnimationFrame(animRef.current);
    };
  }, [selectedId]);

  // Mouse handlers
  const onMouseDown = useCallback((e: MouseEvent) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const cx = e.clientX - rect.left;
    const cy = e.clientY - rect.top;

    const hit = hitTest(nodesRef.current, cx, cy, zoomRef.current, panRef.current.x, panRef.current.y);
    if (hit) {
      hit.pinned = true;
      const worldX = (cx - panRef.current.x) / zoomRef.current;
      const worldY = (cy - panRef.current.y) / zoomRef.current;
      dragRef.current = { node: hit, offsetX: hit.x - worldX, offsetY: hit.y - worldY };
    } else {
      panDragRef.current = { startX: e.clientX, startY: e.clientY, panX: panRef.current.x, panY: panRef.current.y };
    }
  }, []);

  const onMouseMove = useCallback((e: MouseEvent) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const cx = e.clientX - rect.left;
    const cy = e.clientY - rect.top;

    if (dragRef.current) {
      const { node, offsetX, offsetY } = dragRef.current;
      const worldX = (cx - panRef.current.x) / zoomRef.current;
      const worldY = (cy - panRef.current.y) / zoomRef.current;
      node.x = worldX + offsetX;
      node.y = worldY + offsetY;
      node.vx = 0;
      node.vy = 0;
    } else if (panDragRef.current) {
      panRef.current = {
        x: panDragRef.current.panX + (e.clientX - panDragRef.current.startX),
        y: panDragRef.current.panY + (e.clientY - panDragRef.current.startY),
      };
    }
  }, []);

  const onMouseUp = useCallback((e: MouseEvent) => {
    if (dragRef.current) {
      const node = dragRef.current.node;
      node.pinned = false;
      // Check if this was a click (no significant movement)
      const canvas = canvasRef.current;
      if (canvas) {
        const rect = canvas.getBoundingClientRect();
        const cx = e.clientX - rect.left;
        const cy = e.clientY - rect.top;
        const hit = hitTest(nodesRef.current, cx, cy, zoomRef.current, panRef.current.x, panRef.current.y);
        if (hit && hit.id === node.id) {
          setSelectedId((prev) => (prev === node.id ? null : node.id));
        }
      }
      dragRef.current = null;
    }
    panDragRef.current = null;
  }, []);

  const onWheel = useCallback((e: WheelEvent) => {
    e.preventDefault();
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const cx = e.clientX - rect.left;
    const cy = e.clientY - rect.top;

    const oldZoom = zoomRef.current;
    const factor = e.deltaY < 0 ? 1.1 : 0.9;
    const newZoom = Math.max(0.2, Math.min(5, oldZoom * factor));

    // Zoom towards cursor
    panRef.current = {
      x: cx - (cx - panRef.current.x) * (newZoom / oldZoom),
      y: cy - (cy - panRef.current.y) * (newZoom / oldZoom),
    };
    zoomRef.current = newZoom;
    forceRender((n) => n + 1);
  }, []);

  // Resize observer
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || !canvas.parentElement) return;
    const observer = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const w = entry.contentRect.width;
        const h = entry.contentRect.height;
        sizeRef.current = { w, h };
        canvas.width = w * devicePixelRatio;
        canvas.height = h * devicePixelRatio;
        canvas.style.width = `${w}px`;
        canvas.style.height = `${h}px`;
      }
    });
    observer.observe(canvas.parentElement);
    return () => observer.disconnect();
  }, []);

  if (loading) return <div class="loading">Loading graph...</div>;
  if (error) return <div class="error-banner">{error}</div>;
  if (!data) return null;

  const resp = data as GraphScopeResponse;
  const edges = resp.edges ?? [];
  const nodes = resp.nodes ?? [];

  // Fallback to table for empty or oversized graphs
  if (edges.length === 0 || edges.length > MAX_EDGES_FOR_GRAPH) {
    return <EdgeTable edges={edges} />;
  }

  // Selected node details
  const selectedNode = nodes.find((n) => n.id === selectedId);
  const selectedEdges = selectedId
    ? edges.filter((e) => e.from === selectedId || e.to === selectedId)
    : [];

  // Unique relation types for legend
  const relationTypes = [...new Set(edges.map((e) => e.relation))];

  return (
    <div style={{ display: "flex", gap: "16px", height: "100%" }}>
      <div style={{ flex: 1, display: "flex", flexDirection: "column", minHeight: "500px" }}>
        {/* Toolbar */}
        <div class="graph-toolbar">
          <div style={{ display: "flex", alignItems: "center", gap: "12px" }}>
            <span style={{ fontSize: "12px", fontWeight: 600, color: "var(--text-dim)", textTransform: "uppercase", letterSpacing: "0.5px" }}>
              Knowledge Graph
            </span>
            <span style={{ fontSize: "11px", color: "var(--text-dim)", fontFamily: "var(--font-mono)" }}>
              {nodes.length} nodes &middot; {edges.length} edges
            </span>
          </div>
          <div style={{ display: "flex", gap: "8px", alignItems: "center" }}>
            {relationTypes.map((r) => (
              <span
                key={r}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "4px",
                  fontSize: "10px",
                  color: "var(--text-dim)",
                }}
              >
                <span
                  style={{
                    width: "8px",
                    height: "8px",
                    borderRadius: "50%",
                    background: relationColor(r),
                    display: "inline-block",
                  }}
                />
                {r}
              </span>
            ))}
          </div>
          <span class="graph-hint">Drag nodes &middot; Scroll to zoom &middot; Click to select</span>
        </div>

        {/* Canvas */}
        <div
          style={{
            flex: 1,
            position: "relative",
            background: "var(--bg-card)",
            borderRadius: "0 0 var(--radius-md) var(--radius-md)",
            overflow: "hidden",
            border: "1px solid var(--border)",
            borderTop: "none",
          }}
        >
          <canvas
            ref={canvasRef}
            onMouseDown={onMouseDown}
            onMouseMove={onMouseMove}
            onMouseUp={onMouseUp}
            onMouseLeave={onMouseUp}
            onWheel={onWheel}
            style={{ cursor: dragRef.current ? "grabbing" : "grab", display: "block" }}
          />
        </div>
      </div>

      {/* Detail panel */}
      {selectedNode && (
        <div
          style={{
            width: "280px",
            flexShrink: 0,
            display: "flex",
            flexDirection: "column",
            gap: "12px",
          }}
        >
          <div class="trace-card">
            <div style={{ marginBottom: "10px" }}>
              <div style={{ fontSize: "13px", fontWeight: 700, color: "var(--text-bright)", marginBottom: "4px" }}>
                Selected Node
              </div>
              <div
                style={{
                  fontSize: "11px",
                  fontFamily: "var(--font-mono)",
                  color: "var(--gold)",
                  marginBottom: "8px",
                  wordBreak: "break-all",
                }}
              >
                {selectedNode.id}
              </div>
              <div
                style={{
                  fontSize: "12px",
                  color: "var(--text-muted)",
                  lineHeight: "1.5",
                  padding: "10px",
                  background: "var(--bg-primary)",
                  borderRadius: "var(--radius-xs)",
                  maxHeight: "120px",
                  overflowY: "auto",
                  whiteSpace: "pre-wrap",
                  wordBreak: "break-word",
                }}
              >
                {selectedNode.label}
              </div>
            </div>
          </div>

          <div class="trace-card">
            <div style={{ fontSize: "11px", fontWeight: 600, color: "var(--text-dim)", textTransform: "uppercase", letterSpacing: "0.5px", marginBottom: "10px" }}>
              Connections ({selectedEdges.length})
            </div>
            {selectedEdges.length === 0 ? (
              <div class="trace-empty">No edges</div>
            ) : (
              <div style={{ display: "flex", flexDirection: "column", gap: "6px" }}>
                {selectedEdges.map((e, i) => {
                  const isOutgoing = e.from === selectedId;
                  const otherId = isOutgoing ? e.to : e.from;
                  const otherNode = nodes.find((n) => n.id === otherId);
                  return (
                    <div
                      key={i}
                      style={{
                        display: "flex",
                        alignItems: "center",
                        gap: "8px",
                        padding: "6px 8px",
                        background: "var(--bg-elevated)",
                        borderRadius: "var(--radius-xs)",
                        cursor: "pointer",
                      }}
                      onClick={() => setSelectedId(otherId)}
                    >
                      <span
                        style={{
                          fontSize: "10px",
                          color: isOutgoing ? "var(--mint)" : "var(--peach)",
                          fontWeight: 700,
                          width: "16px",
                        }}
                      >
                        {isOutgoing ? "\u2192" : "\u2190"}
                      </span>
                      <span
                        style={{
                          fontSize: "11px",
                          fontFamily: "var(--font-mono)",
                          color: relationColor(e.relation),
                          fontWeight: 600,
                          flexShrink: 0,
                        }}
                      >
                        {e.relation}
                      </span>
                      <span
                        style={{
                          fontSize: "11px",
                          color: "var(--text-muted)",
                          overflow: "hidden",
                          textOverflow: "ellipsis",
                          whiteSpace: "nowrap",
                          flex: 1,
                        }}
                        title={otherNode?.label}
                      >
                        {otherNode?.label
                          ? otherNode.label.length > 30
                            ? otherNode.label.slice(0, 28) + "\u2026"
                            : otherNode.label
                          : shortId(otherId)}
                      </span>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

// --- Fallback table ---

function EdgeTable({ edges }: { edges: GraphScopeEdge[] }) {
  return (
    <div class="card graph-edges">
      <h2>
        Knowledge Graph ({edges.length} edges)
        {edges.length > MAX_EDGES_FOR_GRAPH && (
          <span style={{ fontWeight: 400, fontSize: "11px", color: "var(--text-dim)", marginLeft: "8px" }}>
            (table view — too many edges for visualization)
          </span>
        )}
      </h2>
      {edges.length === 0 ? (
        <div style={{ color: "var(--text-dim)", textAlign: "center", padding: "20px" }}>
          No graph edges found
        </div>
      ) : (
        <table>
          <thead>
            <tr>
              <th>From</th>
              <th>Relation</th>
              <th>To</th>
              <th style={{ width: "80px" }}>Weight</th>
            </tr>
          </thead>
          <tbody>
            {edges.map((e, i) => (
              <tr key={i}>
                <td title={e.from}>{shortId(e.from)}</td>
                <td class="relation">{e.relation}</td>
                <td title={e.to}>{shortId(e.to)}</td>
                <td>{e.weight?.toFixed(2) ?? "\u2014"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

function shortId(id: string): string {
  if (id.length > 12) return id.slice(0, 8) + "\u2026" + id.slice(-4);
  return id;
}
