import { useState, useCallback } from "preact/hooks";
import { fetchEntryHistory } from "../api";
import type { HistoryEntry, HistoryResponse } from "../types";

/** Simple line-by-line diff between two strings. */
function computeDiff(a: string, b: string): { type: "same" | "add" | "del"; text: string }[] {
  const aLines = a.split("\n");
  const bLines = b.split("\n");
  const result: { type: "same" | "add" | "del"; text: string }[] = [];

  // LCS-based diff for accurate results
  const m = aLines.length;
  const n = bLines.length;
  const dp: number[][] = Array.from({ length: m + 1 }, () => Array(n + 1).fill(0));
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      dp[i][j] = aLines[i - 1] === bLines[j - 1] ? dp[i - 1][j - 1] + 1 : Math.max(dp[i - 1][j], dp[i][j - 1]);
    }
  }

  // Backtrack to build diff
  let i = m, j = n;
  const ops: { type: "same" | "add" | "del"; text: string }[] = [];
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && aLines[i - 1] === bLines[j - 1]) {
      ops.push({ type: "same", text: aLines[i - 1] });
      i--; j--;
    } else if (j > 0 && (i === 0 || dp[i][j - 1] >= dp[i - 1][j])) {
      ops.push({ type: "add", text: bLines[j - 1] });
      j--;
    } else {
      ops.push({ type: "del", text: aLines[i - 1] });
      i--;
    }
  }
  ops.reverse();
  return ops.length > 0 ? ops : result;
}

function formatTimestamp(iso: string): string {
  try {
    const d = new Date(iso);
    return d.toLocaleString(undefined, {
      year: "numeric", month: "short", day: "numeric",
      hour: "2-digit", minute: "2-digit", second: "2-digit",
      hour12: false,
    });
  } catch {
    return iso;
  }
}

function truncate(s: string, maxLen: number): string {
  return s.length > maxLen ? s.slice(0, maxLen) + "..." : s;
}

function DiffView({ older, newer }: { older: HistoryEntry; newer: HistoryEntry }) {
  const diff = computeDiff(older.content, newer.content);
  return (
    <div class="history-diff">
      <div class="diff-header">
        <span class="diff-label del-label">v{older.id.slice(0, 8)}...</span>
        <span class="diff-arrow">&rarr;</span>
        <span class="diff-label add-label">v{newer.id.slice(0, 8)}...</span>
      </div>
      <pre class="diff-body">
        {diff.map((line, i) => (
          <div key={i} class={`diff-line ${line.type}`}>
            <span class="diff-marker">{line.type === "add" ? "+" : line.type === "del" ? "-" : " "}</span>
            <span class="diff-text">{line.text}</span>
          </div>
        ))}
      </pre>
    </div>
  );
}

function TimelineNode({
  entry,
  index,
  total,
  isSelected,
  onClick,
}: {
  entry: HistoryEntry;
  index: number;
  total: number;
  isSelected: boolean;
  onClick: () => void;
}) {
  return (
    <button class={`timeline-node${isSelected ? " selected" : ""}`} onClick={onClick}>
      <div class="timeline-connector">
        <div class={`timeline-dot${entry.is_current ? " current" : ""}`} />
        {index < total - 1 && <div class="timeline-line" />}
      </div>
      <div class="timeline-content">
        <div class="timeline-header">
          <span class="timeline-version">v{total - index}</span>
          {entry.is_current && <span class="timeline-badge current">current</span>}
          {entry.valid_to && !entry.is_current && <span class="timeline-badge superseded">superseded</span>}
        </div>
        <div class="timeline-time">{formatTimestamp(entry.valid_from)}</div>
        <div class="timeline-preview">{truncate(entry.content, 120)}</div>
        <div class="timeline-id">{entry.id}</div>
      </div>
    </button>
  );
}

export function HistoryView() {
  const [entryId, setEntryId] = useState("");
  const [data, setData] = useState<HistoryResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selectedIdx, setSelectedIdx] = useState(0);
  const [diffPair, setDiffPair] = useState<[number, number] | null>(null);

  const lookup = useCallback(async () => {
    const id = entryId.trim();
    if (!id) return;
    setLoading(true);
    setError(null);
    setData(null);
    setDiffPair(null);
    setSelectedIdx(0);
    try {
      const resp = await fetchEntryHistory(id);
      setData(resp);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e));
    }
    setLoading(false);
  }, [entryId]);

  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => { if (e.key === "Enter") lookup(); },
    [lookup],
  );

  const chain = data?.chain ?? [];
  const sliderMax = Math.max(chain.length - 1, 0);
  const selectedEntry = chain[selectedIdx] ?? null;

  return (
    <div class="history-view">
      {/* Lookup bar */}
      <div class="history-lookup">
        <input
          type="text"
          class="history-input"
          placeholder="Enter entry ID (UUID)..."
          value={entryId}
          onInput={(e) => setEntryId((e.target as HTMLInputElement).value)}
          onKeyDown={handleKeyDown}
        />
        <button class="history-btn" onClick={lookup} disabled={loading || !entryId.trim()}>
          {loading ? "Loading..." : "Lookup"}
        </button>
      </div>

      {error && <div class="history-error">{error}</div>}

      {data && chain.length === 0 && (
        <div class="history-empty">No supersession chain found for this entry.</div>
      )}

      {chain.length > 0 && (
        <div class="history-content">
          {/* Left: Timeline */}
          <div class="history-timeline">
            <div class="timeline-count">{chain.length} version{chain.length !== 1 ? "s" : ""}</div>
            {chain.map((entry, i) => (
              <TimelineNode
                key={entry.id}
                entry={entry}
                index={i}
                total={chain.length}
                isSelected={selectedIdx === i}
                onClick={() => { setSelectedIdx(i); setDiffPair(null); }}
              />
            ))}
            {chain.length >= 2 && (
              <div class="diff-controls">
                <div class="diff-controls-label">Compare versions</div>
                <div class="diff-selectors">
                  <select
                    class="diff-select"
                    value={diffPair ? String(diffPair[0]) : ""}
                    onChange={(e) => {
                      const v = parseInt((e.target as HTMLSelectElement).value);
                      if (!isNaN(v)) setDiffPair([v, diffPair?.[1] ?? Math.max(v - 1, 0)]);
                    }}
                  >
                    <option value="" disabled>Older...</option>
                    {chain.map((_, i) => (
                      <option key={i} value={String(i)}>v{chain.length - i}</option>
                    ))}
                  </select>
                  <span class="diff-vs">vs</span>
                  <select
                    class="diff-select"
                    value={diffPair ? String(diffPair[1]) : ""}
                    onChange={(e) => {
                      const v = parseInt((e.target as HTMLSelectElement).value);
                      if (!isNaN(v)) setDiffPair([diffPair?.[0] ?? Math.min(v + 1, chain.length - 1), v]);
                    }}
                  >
                    <option value="" disabled>Newer...</option>
                    {chain.map((_, i) => (
                      <option key={i} value={String(i)}>v{chain.length - i}</option>
                    ))}
                  </select>
                </div>
              </div>
            )}
          </div>

          {/* Right: Detail / Diff */}
          <div class="history-detail">
            {/* Time travel slider */}
            {chain.length > 1 && (
              <div class="time-slider">
                <span class="slider-label">Oldest</span>
                <input
                  type="range"
                  min={0}
                  max={sliderMax}
                  value={sliderMax - selectedIdx}
                  onInput={(e) => setSelectedIdx(sliderMax - parseInt((e.target as HTMLInputElement).value))}
                  class="slider-input"
                />
                <span class="slider-label">Newest</span>
              </div>
            )}

            {/* Diff view */}
            {diffPair && chain[diffPair[0]] && chain[diffPair[1]] && diffPair[0] !== diffPair[1] && (
              <DiffView
                older={chain[diffPair[0]]}
                newer={chain[diffPair[1]]}
              />
            )}

            {/* Entry detail */}
            {selectedEntry && (
              <div class="entry-detail-card">
                <div class="entry-detail-header">
                  <span class="entry-detail-version">Version {chain.length - selectedIdx}</span>
                  {selectedEntry.is_current && <span class="timeline-badge current">current</span>}
                </div>
                <div class="entry-detail-meta">
                  <div class="meta-row"><span class="meta-key">ID</span><span class="meta-val mono">{selectedEntry.id}</span></div>
                  <div class="meta-row"><span class="meta-key">Valid from</span><span class="meta-val">{formatTimestamp(selectedEntry.valid_from)}</span></div>
                  {selectedEntry.valid_to && (
                    <div class="meta-row"><span class="meta-key">Valid to</span><span class="meta-val">{formatTimestamp(selectedEntry.valid_to)}</span></div>
                  )}
                  {selectedEntry.superseded_by && (
                    <div class="meta-row"><span class="meta-key">Superseded by</span><span class="meta-val mono">{selectedEntry.superseded_by}</span></div>
                  )}
                  {selectedEntry.metadata.source_file && (
                    <div class="meta-row"><span class="meta-key">Source</span><span class="meta-val">{selectedEntry.metadata.source_file}</span></div>
                  )}
                  {selectedEntry.metadata.language && (
                    <div class="meta-row"><span class="meta-key">Language</span><span class="meta-val">{selectedEntry.metadata.language}</span></div>
                  )}
                </div>
                <div class="entry-detail-content">
                  <div class="content-label">Content</div>
                  <pre class="content-body">{selectedEntry.content}</pre>
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
