import type {
  DashboardStatusResponse,
  LogsResponse,
  TracesResponse,
  GraphEdge,
  GraphScopeResponse,
  DashboardConfig,
  AgentRecord,
  SessionRecord,
  MergeQueueStatus,
  RagResponse,
  HealthResponse,
  EntryDetail,
  HistoryResponse,
} from "./types";

const BASE = "/api/dashboard";

async function get<T>(path: string): Promise<T> {
  const resp = await fetch(`${BASE}${path}`);
  if (!resp.ok) throw new Error(`${resp.status} ${resp.statusText}`);
  return resp.json();
}

async function post<T>(path: string, body: unknown): Promise<T> {
  const resp = await fetch(`${BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!resp.ok) throw new Error(`${resp.status} ${resp.statusText}`);
  return resp.json();
}

export function fetchStatus(): Promise<DashboardStatusResponse> {
  return get("/status");
}

export function fetchTraces(): Promise<TracesResponse> {
  return get("/traces");
}

export function fetchLogs(params?: {
  module?: string;
  level?: string;
  limit?: number;
}): Promise<LogsResponse> {
  const q = new URLSearchParams();
  if (params?.module) q.set("module", params.module);
  if (params?.level) q.set("level", params.level);
  if (params?.limit) q.set("limit", String(params.limit));
  const qs = q.toString();
  return get(`/logs${qs ? `?${qs}` : ""}`);
}

export function fetchConfig(): Promise<DashboardConfig> {
  return get("/config");
}

export function fetchGraph(entryId?: string): Promise<GraphEdge[]> {
  const qs = entryId ? `?entry_id=${entryId}` : "";
  return get(`/graph${qs}`);
}

// --- Graph (scope-level) ---

export function fetchGraphScope(): Promise<GraphScopeResponse> {
  return get("/graph/scope");
}

// --- Agents ---

export function fetchAgents(): Promise<AgentRecord[]> {
  return get("/agents");
}

export function fetchAgentSessions(agentId: string): Promise<SessionRecord[]> {
  return get(`/agents/${encodeURIComponent(agentId)}/sessions`);
}

// --- Merge queue ---

export function fetchMergeQueue(limit?: number): Promise<MergeQueueStatus> {
  const qs = limit ? `?limit=${limit}` : "";
  return get(`/merge/queue${qs}`);
}

export function retryMergeEntries(entryIds: string[]): Promise<{ retried: number }> {
  return post("/merge/retry", { entry_ids: entryIds });
}

// --- RAG ---

export function ragAsk(query: string, scopeId: string): Promise<RagResponse> {
  return post("/rag/ask", { query, scope_id: scopeId });
}

// --- Entry / History ---

export function fetchEntryDetail(entryId: string): Promise<EntryDetail> {
  return get(`/entries/${encodeURIComponent(entryId)}`);
}

export function fetchEntryHistory(entryId: string): Promise<HistoryResponse> {
  return get(`/entries/${encodeURIComponent(entryId)}/history`);
}

// --- Health ---

export function fetchHealth(check?: string): Promise<HealthResponse> {
  const qs = check ? `?check=${check}` : "";
  return get(`/health${qs}`);
}
