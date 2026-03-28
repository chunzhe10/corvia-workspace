import { useState, useCallback } from "preact/hooks";
import { usePoll } from "../hooks/use-poll";
import { fetchTiers, fetchTierTransitions, fetchPinnedEntries, fetchGcCycleHistory, unpinEntry } from "../api";
import type { TiersResponse, TierTransitionsResponse, PinnedEntriesResponse, GcCycleHistoryResponse } from "../types";

// --- Tier colors ---
const TIER_COLORS: Record<string, string> = {
  hot: "var(--coral)",
  warm: "var(--peach)",
  cold: "var(--sky)",
  forgotten: "var(--text-dim)",
};

const TIER_BG: Record<string, string> = {
  hot: "var(--coral-soft)",
  warm: "var(--peach-soft)",
  cold: "var(--sky-soft)",
  forgotten: "rgba(138, 130, 121, 0.10)",
};

// --- Disabled banner ---
function DisabledBanner() {
  return (
    <div class="tier-disabled-banner">
      <span class="tier-disabled-icon" aria-hidden="true">&#x26A0;</span>
      <div>
        <div style={{ fontWeight: 600, marginBottom: "2px" }}>Forgetting is disabled</div>
        <div style={{ fontSize: "12px", color: "var(--text-dim)" }}>
          All entries are treated as Hot. Enable forgetting in corvia.toml to activate tier lifecycle.
        </div>
      </div>
    </div>
  );
}

// --- 1. Tier Distribution Chart ---
function TierDistributionChart({ data }: { data: TiersResponse }) {
  if (data.total === 0) {
    return (
      <div class="trace-card">
        <h2 class="tier-section-title">Tier Distribution</h2>
        <div class="tier-empty">No entries in knowledge store. Ingest content or write via the API to populate.</div>
      </div>
    );
  }

  const tiers = [
    { key: "hot", label: "Hot", count: data.hot },
    { key: "warm", label: "Warm", count: data.warm },
    { key: "cold", label: "Cold", count: data.cold },
    { key: "forgotten", label: "Forgotten", count: data.forgotten },
  ];

  return (
    <div class="trace-card">
      <h2 class="tier-section-title">Tier Distribution</h2>

      {/* Stacked bar */}
      <div class="tier-bar" role="img" aria-label={`Tier distribution: ${tiers.map((t) => `${t.label} ${t.count}`).join(", ")} of ${data.total} total`}>
        {tiers.map((t) => {
          const pct = (t.count / data.total) * 100;
          if (pct === 0) return null;
          return (
            <div
              key={t.key}
              class="tier-bar-segment"
              style={{ width: `${pct}%`, background: TIER_COLORS[t.key] }}
              title={`${t.label}: ${t.count} (${pct.toFixed(1)}%)`}
            />
          );
        })}
      </div>

      {/* Legend */}
      <div class="tier-legend">
        {tiers.map((t) => (
          <div class="tier-legend-item" key={t.key}>
            <div class="tier-legend-dot" style={{ background: TIER_COLORS[t.key] }} />
            <span class="tier-legend-label">{t.label}</span>
            <span class="tier-legend-count">{t.count.toLocaleString()}</span>
            <span class="tier-legend-pct">
              {((t.count / data.total) * 100).toFixed(1)}%
            </span>
          </div>
        ))}
      </div>

      {/* Total */}
      <div class="tier-total">
        {data.total.toLocaleString()} total entries
      </div>
    </div>
  );
}

// --- 2. Recent Transitions Table ---
function RecentTransitions({ data, navigateToHistory }: { data: TierTransitionsResponse; navigateToHistory?: (entryId: string) => void }) {
  return (
    <div class="trace-card">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "10px" }}>
        <h2 class="tier-section-title" style={{ margin: 0 }}>Recent Transitions</h2>
        <span style={{ fontSize: "11px", color: "var(--text-dim)" }}>
          {data.count} transition{data.count !== 1 ? "s" : ""}
        </span>
      </div>

      {data.transitions.length === 0 ? (
        <div class="tier-empty">No tier transitions recorded yet. Transitions appear after a GC cycle runs.</div>
      ) : (
        <div class="tier-table-wrap" tabindex={0} role="region" aria-label="Recent tier transitions">
          <table class="tier-table">
            <thead>
              <tr>
                <th>Entry</th>
                <th>From</th>
                <th>To</th>
                <th>Score</th>
                <th>Reason</th>
                <th>Time</th>
              </tr>
            </thead>
            <tbody>
              {data.transitions.map((t, i) => (
                <tr key={i}>
                  <td>
                    {navigateToHistory ? (
                      <code class="tier-entry-id entry-link" onClick={() => navigateToHistory(t.entry_id)} style={{ cursor: "pointer" }}>{t.entry_id.slice(0, 8)}</code>
                    ) : (
                      <code class="tier-entry-id">{t.entry_id.slice(0, 8)}</code>
                    )}
                  </td>
                  <td>
                    <span class="tier-badge" style={{ background: TIER_BG[t.from_tier.toLowerCase()] || TIER_BG.forgotten, color: TIER_COLORS[t.from_tier.toLowerCase()] || TIER_COLORS.forgotten }}>
                      {t.from_tier}
                    </span>
                  </td>
                  <td>
                    <span class="tier-badge" style={{ background: TIER_BG[t.to_tier.toLowerCase()] || TIER_BG.forgotten, color: TIER_COLORS[t.to_tier.toLowerCase()] || TIER_COLORS.forgotten }}>
                      {t.to_tier}
                    </span>
                  </td>
                  <td class="tier-score">{t.retention_score.toFixed(3)}</td>
                  <td class="tier-reason" title={t.reason}>{t.reason}</td>
                  <td class="tier-time">{shortTs(t.timestamp)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

// --- 3. Pinned Entries List ---
function PinnedEntries({ data, onUnpin, unpinning, navigateToHistory }: { data: PinnedEntriesResponse; onUnpin: (id: string) => void; unpinning: string | null; navigateToHistory?: (entryId: string) => void }) {
  return (
    <div class="trace-card">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "10px" }}>
        <h2 class="tier-section-title" style={{ margin: 0 }}>Pinned Entries</h2>
        <span style={{ fontSize: "11px", color: "var(--text-dim)" }}>
          {data.count} pinned
        </span>
      </div>

      {data.entries.length === 0 ? (
        <div class="tier-empty">No pinned entries. Pin entries via the CLI or MCP tools to protect them from forgetting.</div>
      ) : (
        <div class="tier-pinned-list" tabindex={0} role="region" aria-label="Pinned entries list">
          {data.entries.map((entry) => (
            <div class="tier-pinned-item" key={entry.entry_id}>
              <div class="tier-pinned-content">
                {navigateToHistory ? (
                  <code class="tier-entry-id entry-link" onClick={() => navigateToHistory(entry.entry_id)} style={{ cursor: "pointer" }}>{entry.entry_id.slice(0, 8)}</code>
                ) : (
                  <code class="tier-entry-id">{entry.entry_id.slice(0, 8)}</code>
                )}
                <div class="tier-pinned-preview">{entry.content_preview}</div>
                <div class="tier-pinned-meta">
                  Pinned by {entry.pinned_by} on {new Date(entry.pinned_at).toLocaleDateString()}
                </div>
              </div>
              <button
                class="tier-unpin-btn"
                onClick={() => onUnpin(entry.entry_id)}
                disabled={unpinning === entry.entry_id}
                title="Unpin entry"
              >
                {unpinning === entry.entry_id ? "Unpinning..." : "Unpin"}
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// --- 4. GC History Timeline ---
function GcHistoryTimeline({ data }: { data: GcCycleHistoryResponse }) {
  if (data.cycles.length === 0) {
    return (
      <div class="trace-card">
        <h2 class="tier-section-title">GC Cycle History</h2>
        <div class="tier-empty">No knowledge GC cycles recorded yet. Enable forgetting in corvia.toml to start lifecycle management.</div>
      </div>
    );
  }

  // Sparkline of cycle durations
  const maxDuration = Math.max(...data.cycles.map((c) => c.cycle_duration_ms), 1);
  const barW = Math.max(6, Math.floor(320 / data.cycles.length));
  const h = 60;

  const totalTransitions = (c: typeof data.cycles[0]) =>
    c.hot_to_warm + c.warm_to_cold + c.cold_to_forgotten + c.warm_to_hot + c.cold_to_warm;

  return (
    <div class="trace-card">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: "10px" }}>
        <h2 class="tier-section-title" style={{ margin: 0 }}>GC Cycle History</h2>
        <span style={{ fontSize: "11px", color: "var(--text-dim)" }}>
          {data.count} cycle{data.count !== 1 ? "s" : ""}
        </span>
      </div>

      {/* Duration sparkline */}
      <svg width={barW * data.cycles.length + 4} height={h} class="gc-sparkline" role="img" aria-label="GC cycle duration chart">
        {data.cycles.map((c, i) => {
          const barH = Math.max(2, (c.cycle_duration_ms / maxDuration) * (h - 4));
          const color = c.circuit_breaker_tripped
            ? "var(--coral)"
            : c.hnsw_rebuild_triggered
              ? "var(--amber)"
              : "var(--mint)";
          return (
            <rect
              key={i}
              x={i * barW + 2}
              y={h - barH - 2}
              width={barW - 2}
              height={barH}
              fill={color}
              rx={1}
            >
              <title>
                {c.cycle_duration_ms}ms, {c.entries_scanned} scanned, {totalTransitions(c)} transitions
                {c.hnsw_rebuild_triggered ? " (rebuild)" : ""}
              </title>
            </rect>
          );
        })}
      </svg>

      {/* Latest cycle details */}
      {data.cycles.length > 0 && (() => {
        const latest = data.cycles[data.cycles.length - 1];
        return (
          <div class="tier-gc-details">
            <div class="mini-stats">
              <div class="mini-stat">
                <div class="mini-stat-val">{latest.entries_scanned}</div>
                <div class="mini-stat-lbl">Scanned</div>
              </div>
              <div class="mini-stat">
                <div class="mini-stat-val" style={{ color: "var(--coral)" }}>{latest.hot_to_warm + latest.warm_to_cold + latest.cold_to_forgotten}</div>
                <div class="mini-stat-lbl">Demotions</div>
              </div>
              <div class="mini-stat">
                <div class="mini-stat-val" style={{ color: "var(--mint)" }}>{latest.warm_to_hot + latest.cold_to_warm}</div>
                <div class="mini-stat-lbl">Promotions</div>
              </div>
              <div class="mini-stat">
                <div class="mini-stat-val">{latest.cycle_duration_ms}<span style={{ fontSize: "11px" }}>ms</span></div>
                <div class="mini-stat-lbl">Duration</div>
              </div>
            </div>

            {/* Transition breakdown */}
            <div class="tier-gc-transitions">
              {latest.hot_to_warm > 0 && <span class="tier-gc-flow">Hot&#x2192;Warm: {latest.hot_to_warm}</span>}
              {latest.warm_to_cold > 0 && <span class="tier-gc-flow">Warm&#x2192;Cold: {latest.warm_to_cold}</span>}
              {latest.cold_to_forgotten > 0 && <span class="tier-gc-flow">Cold&#x2192;Forgotten: {latest.cold_to_forgotten}</span>}
              {latest.warm_to_hot > 0 && <span class="tier-gc-flow tier-gc-promo">Warm&#x2192;Hot: {latest.warm_to_hot}</span>}
              {latest.cold_to_warm > 0 && <span class="tier-gc-flow tier-gc-promo">Cold&#x2192;Warm: {latest.cold_to_warm}</span>}
              {latest.chain_protected > 0 && <span class="tier-gc-flow tier-gc-protect">Chain protected: {latest.chain_protected}</span>}
              {latest.auto_protected > 0 && <span class="tier-gc-flow tier-gc-protect">Auto protected: {latest.auto_protected}</span>}
            </div>

            {latest.hnsw_rebuild_triggered && (
              <div style={{ fontSize: "11px", color: "var(--amber)", marginTop: "6px" }}>
                HNSW rebuild triggered ({latest.rebuild_duration_ms}ms)
              </div>
            )}
          </div>
        );
      })()}
    </div>
  );
}

// --- Helpers ---
function shortTs(ts: string): string {
  if (/^\d{2}:\d{2}:\d{2}/.test(ts)) return ts;
  try {
    const d = new Date(ts);
    if (isNaN(d.getTime())) return ts;
    return d.toLocaleTimeString([], { hour12: false });
  } catch { return ts; }
}

// --- Main TiersView ---
export function TiersView({ navigateToHistory }: { navigateToHistory?: (entryId: string) => void }) {
  const [unpinning, setUnpinning] = useState<string | null>(null);

  const tiersFetcher = useCallback(() => fetchTiers(), []);
  const transitionsFetcher = useCallback(() => fetchTierTransitions(50), []);
  const pinnedFetcher = useCallback(() => fetchPinnedEntries(), []);
  const gcFetcher = useCallback(() => fetchGcCycleHistory(), []);

  const { data: tiers, loading: tiersLoading, error: tiersError } = usePoll(tiersFetcher, 10000);
  const { data: transitions } = usePoll(transitionsFetcher, 15000);
  const { data: pinned } = usePoll(pinnedFetcher, 10000);
  const { data: gcHistory } = usePoll(gcFetcher, 15000);

  const handleUnpin = useCallback(async (entryId: string) => {
    if (!window.confirm("Unpin this entry? It will become eligible for forgetting.")) return;
    setUnpinning(entryId);
    try {
      await unpinEntry(entryId);
    } catch { /* next poll picks up */ }
    setUnpinning(null);
  }, []);

  if (tiersLoading && !tiers) {
    return <div class="loading">Loading tier data...</div>;
  }

  return (
    <div class="tiers-view">
      {tiersError && <div class="error-banner">{tiersError}</div>}
      {tiers && !tiers.forgetting_enabled && <DisabledBanner />}

      <div style={tiers && !tiers.forgetting_enabled ? { opacity: 0.5 } : {}} class="tiers-grid">
        {/* Left column: distribution + GC history */}
        <div class="tiers-col">
          {tiers && <TierDistributionChart data={tiers} />}
          {gcHistory && <GcHistoryTimeline data={gcHistory} />}
        </div>

        {/* Right column: transitions + pinned */}
        <div class="tiers-col">
          {transitions && <RecentTransitions data={transitions} navigateToHistory={navigateToHistory} />}
          {pinned && <PinnedEntries data={pinned} onUnpin={handleUnpin} unpinning={unpinning} navigateToHistory={navigateToHistory} />}
        </div>
      </div>
    </div>
  );
}
