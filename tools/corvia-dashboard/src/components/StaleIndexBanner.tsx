import { useState, useCallback, useRef } from "preact/hooks";
import { useEffect } from "preact/hooks";
import type { DashboardStatusResponse } from "../types";

interface Props {
  data: DashboardStatusResponse;
  onRefresh?: () => void;
  refreshing?: boolean;
}

export function StaleIndexBanner({ data, onRefresh, refreshing }: Props) {
  const [dismissed, setDismissed] = useState(false);
  const prevStale = useRef(data.index_stale);

  // Reset dismissed state when index_stale transitions from false/null back to true
  useEffect(() => {
    if (prevStale.current !== true && data.index_stale === true) {
      setDismissed(false);
    }
    prevStale.current = data.index_stale;
  }, [data.index_stale]);

  const handleDismiss = useCallback(() => setDismissed(true), []);

  if (dismissed || data.index_stale !== true) return null;

  const pct = data.index_coverage != null
    ? `${(data.index_coverage * 100).toFixed(1)}%`
    : "unknown";

  const threshold = `${(data.index_stale_threshold * 100).toFixed(0)}%`;

  return (
    <div class="stale-index-banner" role="alert">
      <div class="stale-index-banner__content">
        <span class="stale-index-banner__icon" aria-hidden="true">&#x26A0;</span>
        <div class="stale-index-banner__text">
          <strong>Search index is stale</strong>
          <span class="stale-index-banner__detail">
            Coverage: {pct} (threshold: {threshold}) &mdash; {data.index_hnsw_count} indexed / {data.index_disk_count} on disk
          </span>
        </div>
        <div class="stale-index-banner__actions">
          {onRefresh && (
            <button
              class="stale-index-banner__refresh"
              onClick={onRefresh}
              disabled={refreshing}
              title="Recheck index coverage"
            >
              {refreshing ? "Checking..." : "Recheck"}
            </button>
          )}
          <button
            class="stale-index-banner__dismiss"
            onClick={handleDismiss}
            aria-label="Dismiss stale index warning"
            title="Dismiss"
          >
            &#x2715;
          </button>
        </div>
      </div>
    </div>
  );
}
