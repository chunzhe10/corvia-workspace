# Knowledge Health Benchmarks

Tracks corvia's knowledge base health over time by calling the deterministic
reasoning engine (`/v1/reason`) and comparing results across runs.

## Methodology

1. **Call `/v1/reason`** with `scope_id: "corvia"` to run all five deterministic
   health checks against the knowledge base:
   - **orphaned_node** — entries with zero graph edges (no relations to other knowledge)
   - **stale_knowledge** — entries not updated within the expected freshness window
   - **broken_chain** — supersession chains with missing links
   - **dangling_import** — graph edges pointing to non-existent entries
   - **dependency_cycle** — circular dependency chains in the knowledge graph

2. **Group findings by `check_type`** and count occurrences. Each finding includes
   a confidence score (0.0-1.0) and a rationale explaining the issue.

3. **Compare to previous run** (most recent `results/health-*.json`):
   - Delta in total finding count
   - Delta per check type
   - New check types (regression signal)
   - Resolved check types (improvement signal)

4. **Save results** as timestamped JSON for longitudinal tracking.

## Usage

```bash
# Default: connect to localhost:8020, scope "corvia"
python3 benchmarks/knowledge-health/eval.py

# Custom server/scope
python3 benchmarks/knowledge-health/eval.py --server http://localhost:8020 --scope corvia
```

## Exit Codes

- `0` — Run completed, no new check types detected
- `1` — New check types appeared (potential regression)

## Output

Each run produces:
- A console report with per-type counts and deltas
- A JSON file in `results/health-{timestamp}.json`

### Result JSON Schema

```json
{
  "timestamp": "2026-03-19T12:00:00Z",
  "scope_id": "corvia",
  "total_findings": 3697,
  "check_types_count": 1,
  "groups": {
    "orphaned_node": {
      "count": 3697,
      "sample_rationale": "Entry ... has zero graph edges (no relations)",
      "confidence": 0.8
    }
  },
  "delta": {
    "first_run": false,
    "types": { "orphaned_node": { "current": 3697, "previous": 3600, "delta": 97 } },
    "new_types": [],
    "removed_types": [],
    "previous_file": "2026-03-18T12:00:00Z"
  }
}
```

## Interpreting Results

- **orphaned_node** findings are expected to be high after bulk ingestion (code files
  don't automatically create graph edges). These decrease as agents and the
  relation-discovery pipeline connect entries.
- **stale_knowledge** findings increase naturally over time and indicate entries that
  may need re-ingestion or review.
- A spike in **dangling_edge** or **broken_chain** findings after a GC or rebuild
  may indicate a bug in the cleanup logic.
- **dependency_cycle** findings should always be zero in a healthy knowledge base.

## Dogfooding (`--persist`)

Pass `--persist` to write each health snapshot as a corvia knowledge entry:

```bash
python3 benchmarks/knowledge-health/eval.py --persist
```

This persists the report to corvia with `content_role: "finding"` and
`source_origin: "workspace"`, creating a time-series of health data
inside corvia itself. Query historical snapshots via `corvia_search`
or `corvia_history`.

## CI Integration

The CI quality gate (`benchmarks/ci/health-gate.sh`) runs this eval and
enforces thresholds:

| Check Type | Threshold | Rationale |
|------------|-----------|-----------|
| dependency_cycle | 0 | Data integrity bug |
| broken_chain | 0 | Data integrity bug |
| dangling_import | 0 | Data integrity bug |
| Total findings | <= 12000 | Generous ceiling (baseline ~9200) |

Run locally: `./benchmarks/ci/health-gate.sh`

## Integration with `corvia bench`

The CLI command `corvia bench run` executes the RAG retrieval evaluation suite.
This knowledge-health eval is complementary — it measures structural integrity
of the knowledge base rather than retrieval quality. Together they provide both
a "is the data healthy?" and "can we find the right data?" signal.
