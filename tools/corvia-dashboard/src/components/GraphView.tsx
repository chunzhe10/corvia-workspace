import { useCallback } from "preact/hooks";
import { usePoll } from "../hooks/use-poll";
import { fetchGraph } from "../api";

export function GraphView() {
  const fetcher = useCallback(() => fetchGraph(), []);
  const { data, error, loading } = usePoll(fetcher, 5000);

  if (loading) return <div class="loading">Loading graph...</div>;
  if (error) return <div class="error-banner">{error}</div>;
  if (!data) return null;

  const edges = Array.isArray(data) ? data : [];

  return (
    <div class="card graph-edges">
      <h2>Knowledge Graph ({edges.length} edges)</h2>
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
                <td title={e.from_id}>{shortId(e.from_id)}</td>
                <td class="relation">{e.relation}</td>
                <td title={e.to_id}>{shortId(e.to_id)}</td>
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
