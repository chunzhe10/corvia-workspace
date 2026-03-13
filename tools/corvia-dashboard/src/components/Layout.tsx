import { useState, useCallback } from "preact/hooks";
import { usePoll } from "../hooks/use-poll";
import { fetchStatus, fetchHealth } from "../api";
import { StatusBar } from "./StatusBar";
import { LogsView } from "./LogsView";
import { TracesView } from "./TracesView";
import { GraphView } from "./GraphView";
import { AgentsView } from "./AgentsView";
import { RagView } from "./RagView";
import { HistoryView } from "./HistoryView";
import { ConfigPanel } from "./ConfigPanel";
import { HealthPanel } from "./HealthPanel";
import type { HealthResponse } from "../types";

type Tab = "traces" | "agents" | "rag" | "logs" | "graph" | "history";

const TABS: { id: Tab; label: string }[] = [
  { id: "traces", label: "Traces" },
  { id: "agents", label: "Agents" },
  { id: "rag", label: "RAG" },
  { id: "logs", label: "Logs" },
  { id: "graph", label: "Graph" },
  { id: "history", label: "History" },
];

const FRIENDLY_NAMES: Record<string, string> = {
  "corvia-server": "API Server",
  "corvia-inference": "Inference",
};

type SidebarMode = "config" | "health";

export function Layout() {
  const [tab, setTab] = useState<Tab>("traces");
  const [sidebarMode, setSidebarMode] = useState<SidebarMode>("config");
  const [healthData, setHealthData] = useState<HealthResponse | null>(null);
  const [healthLoading, setHealthLoading] = useState(false);

  const fetcher = useCallback(() => fetchStatus(), []);
  const { data, error, loading } = usePoll(fetcher, 5000);

  const navigateToTab = useCallback((t: string) => setTab(t as Tab), []);

  const loadHealth = useCallback(async () => {
    setSidebarMode("health");
    if (healthData) return; // use cached
    setHealthLoading(true);
    try {
      const h = await fetchHealth();
      setHealthData(h);
    } catch { /* ignore */ }
    setHealthLoading(false);
  }, [healthData]);

  const refreshHealth = useCallback(async () => {
    setHealthLoading(true);
    try {
      const h = await fetchHealth();
      setHealthData(h);
    } catch { /* ignore */ }
    setHealthLoading(false);
  }, []);

  // Summarize health for header dots
  const healthSummary = healthData
    ? {
        total: healthData.count,
        hasErrors: healthData.findings.some((f) => f.confidence > 0.7),
        hasWarnings: healthData.findings.some((f) => f.confidence > 0.3 && f.confidence <= 0.7),
      }
    : null;

  return (
    <div class="layout">
      <header class="header">
        <div class="brand">
          <div class="brand-icon">C</div>
          <span class="brand-name">Corvia</span>
        </div>

        <div class="status-pills">
          {data?.services.map((s) => (
            <div class="pill" key={s.name}>
              <div class={`pill-dot ${s.state === "healthy" ? "ok" : s.state === "starting" ? "warn" : "down"}`} />
              <span class="pill-label">{FRIENDLY_NAMES[s.name] ?? s.name}</span>
              {s.latency_ms != null && (
                <span class="pill-latency">{s.latency_ms.toFixed(1)}ms</span>
              )}
            </div>
          ))}
        </div>

        {/* Health pulse dots */}
        <button
          class={`health-pulse${sidebarMode === "health" ? " active" : ""}`}
          onClick={loadHealth}
          title="Knowledge health"
        >
          <span class={`health-dot ${healthSummary?.hasErrors ? "red" : healthSummary?.hasWarnings ? "amber" : healthSummary ? "green" : ""}`} />
          <span class={`health-dot ${healthSummary && !healthSummary.hasErrors ? "green" : healthSummary?.hasErrors ? "red" : ""}`} />
          <span class={`health-dot ${healthSummary ? "green" : ""}`} />
          {healthSummary && healthSummary.total > 0 && (
            <span class="health-count">{healthSummary.total}</span>
          )}
        </button>

        <nav class="tabs">
          {TABS.map((t) => (
            <button
              key={t.id}
              class={`tab ${tab === t.id ? "active" : ""}`}
              onClick={() => setTab(t.id)}
            >
              {t.label}
            </button>
          ))}
        </nav>

        <div class="header-right">
          {data && (
            <span class="scope-badge">{data.config.workspace}</span>
          )}
          <span class="header-time">{new Date().toLocaleTimeString([], { hour12: false })}</span>
        </div>
      </header>

      <div class="main">
        <div class="content">
          {loading && !data && <div class="loading">Connecting to corvia-server...</div>}
          {error && !data && <div class="error-banner">Unable to reach corvia-server: {error}</div>}

          {data && <StatusBar data={data} />}

          {tab === "traces" && <TracesView onNavigate={navigateToTab} />}
          {tab === "agents" && <AgentsView />}
          {tab === "rag" && <RagView />}
          {tab === "logs" && <LogsView />}
          {tab === "graph" && <GraphView />}
          {tab === "history" && <HistoryView />}
        </div>

        <aside class="sidebar">
          <div class="sidebar-tabs">
            <button
              class={`sidebar-tab${sidebarMode === "config" ? " active" : ""}`}
              onClick={() => setSidebarMode("config")}
            >
              Config
            </button>
            <button
              class={`sidebar-tab${sidebarMode === "health" ? " active" : ""}`}
              onClick={loadHealth}
            >
              Health
            </button>
          </div>
          {sidebarMode === "config" ? (
            data ? (
              <ConfigPanel config={data.config} />
            ) : (
              <div style={{ color: "var(--text-dim)" }}>Waiting for server...</div>
            )
          ) : (
            <HealthPanel
              data={healthData}
              loading={healthLoading}
              onRefresh={refreshHealth}
            />
          )}
        </aside>
      </div>
    </div>
  );
}
