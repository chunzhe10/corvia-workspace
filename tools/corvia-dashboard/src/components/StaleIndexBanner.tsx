import { useState, useCallback } from "preact/hooks";
import type { DashboardStatusResponse } from "../types";

interface Props {
  data: DashboardStatusResponse;
  onRefresh?: () => void;
  refreshing?: boolean;
}

export function StaleIndexBanner({ data, onRefresh, refreshing }: Props) {
  const [dismissed, setDismissed] = useState(false);

  const handleDismiss = useCallback(() => setDismissed(true), []);

  if (dismissed || !data.index_stale) return null;

  const pct = data.index_coverage != null
    ? `${(data.index_coverage * 100).toFixed(1)}%`
    : "unknown";

  return (
    <div class="stale-index-banner">
      <div class="stale-index-banner__content">
        <span class="stale-index-banner__icon">&#x26A0;</span>
        <div class="stale-index-banner__text">
          <strong>Search index is stale</strong>
          <span class="stale-index-banner__detail">
            Coverage: {pct} &mdash; {data.index_hnsw_count} indexed / {data.index_disk_count} on disk
          </span>
        </div>
        <div class="stale-index-banner__actions">
          {onRefresh && (
            <button
              class="stale-index-banner__refresh"
              onClick={onRefresh}
              disabled={refreshing}
              title="Refresh coverage check"
            >
              {refreshing ? "Checking..." : "Refresh"}
            </button>
          )}
          <button
            class="stale-index-banner__dismiss"
            onClick={handleDismiss}
            title="Dismiss"
          >
            &#x2715;
          </button>
        </div>
      </div>
    </div>
  );
}
