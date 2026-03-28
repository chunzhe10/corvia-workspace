# Multi-Spoke Design: 5-Persona Review Summary

**Date:** 2026-03-28
**Status:** COMPLETE -- All fixes incorporated into main design docs
**Reviewers:** Senior SWE, Product Manager, QA Engineer, DevOps Engineer, Security Engineer
**Documents Reviewed:**
- `2026-03-28-multi-spoke-workspace-brainstorm.md`
- `2026-03-28-spoke-cli-design.md`
- `2026-03-28-spoke-dashboard-design.md`
- `2026-03-28-spoke-design-review-fixes.md` (fixes document)

---

## Verdicts

| Reviewer | Verdict | Confidence |
|----------|---------|-----------|
| Senior SWE | With fixes | High |
| Product Manager | With fixes | High |
| QA Engineer | With fixes | Medium |
| DevOps Engineer | With fixes | Medium |
| Security Engineer | **No** (fix C1/C2/I1-I4 first) | High |

---

## Critical Issues (Must Fix Before Implementation)

### C1: HubContext panics on unmapped paths (SWE)
`hub.host_path().unwrap()` panics if no mount matches. Return `Result` with
diagnostic error showing the mount table.

### C2: No duplicate spoke name guard (SWE)
Creating spoke-42 twice gives cryptic Docker 409 error. Check for existing
container before creation, offer `--force` to replace.

### C3: No credential expiry handling (QA)
OAuth tokens expire. Multi-hour dev-loops will hit 401 mid-session. Need to
document token TTL, consider `apiKeyHelper` or `ANTHROPIC_API_KEY` as primary.

### C4: No rollback on partial spoke creation failure (QA)
If entrypoint fails after container creation, orphaned containers accumulate.
Add trap-based cleanup in entrypoint, handle "created" state in prune.

### C5: HubContext fails outside containers (DevOps)
`docker inspect $(hostname)` fails on bare metal/Podman. Add container detection
check, clear error message for unsupported environments.

### C6: Hardcoded/non-deterministic network selection (DevOps, SWE)
`HashMap.keys().next()` picks arbitrary network when hub is on multiple. Filter
out bridge/host/none, prefer networks containing "devcontainer", require config
if ambiguous.

### C7: MCP endpoint on 0.0.0.0 with no authentication (Security)
Any process on the Docker network can call destructive MCP tools (gc_run,
config_set, write). Add bearer token auth, inject token into spokes at creation.

### C8: No failure UX for spoke creation/runtime (PM)
Spokes run headless. Silent failures are invisible. Add prerequisite validation,
startup health gate, failure reason in `spoke list`.

---

## Important Issues (Must Fix During Implementation)

### I1: GITHUB_TOKEN forwarded without validation (SWE, QA, DevOps)
Empty token causes silent failure 30 min into dev-loop. Validate at creation
time, fail fast with clear message.

### I2: No resource limits on spoke containers (PM, QA, DevOps)
5 spokes with no limits will OOM a 16GB host. Add default memory/CPU limits
in SpokeConfig, document recommended spoke counts by machine size.

### I3: Agent identity spoofing via env var (Security)
Any MCP client can claim any agent_id. Generate per-spoke auth token at
creation, validate agent_id + token pair on writes.

### I4: Supply chain risk - `npm install @latest` (Security)
No version pinning or integrity check. Compromised package runs with full
permissions. Pin version in Dockerfile, never use `@latest` at runtime.

### I5: GITHUB_TOKEN scope too broad (Security)
Full `repo` scope when only contents:write + pull_requests:write needed.
Use fine-grained PATs or GitHub App installation tokens.

### I6: No test plan documented (QA)
Large integration surface (Docker, networking, credentials, git, MCP) with
no defined test matrix. Add unit/integration/E2E test plan with platform matrix.

### I7: Entrypoint has no startup error reporting to corvia (SWE, QA)
If git clone fails, spoke exits silently. Add trap handler that writes failure
status to corvia before exiting.

### I8: Shallow clone depth inconsistent and may be insufficient (SWE, PM, QA)
Brainstorm says depth 1, entrypoint says depth 50. Default branch hardcoded
to `master`. Standardize, query default branch via `gh api`.

### I9: Usage agreement risk understated (PM)
Multi-container subscription credential use is the entire value prop. If terms
prohibit it, feature is dead. Elevate to Phase 0 blocker.

### I10: Branch naming from `--issue` underspecified (PM)
No explanation of where branch description comes from, or what happens if
branch already exists on remote.

### I11: Hub restart breaks all spoke MCP connections (DevOps)
No retry logic. Every `corvia-dev` restart stalls all active spokes.

### I12: Disk exhaustion from clones at scale (DevOps)
20 spokes x cargo build = 40-60GB. No disk budget check.

### I13: Spoke permissions maximally permissive (Security)
`Bash(*)` allows arbitrary commands. Consider restricting to needed patterns.

---

## Low Issues (Fix Before Merge)

| # | Issue | Source |
|---|-------|--------|
| L1 | Dashboard Docker client created per request, not cached in AppState | SWE |
| L2 | SpokeConfig nested under two Option levels, needs helper | SWE |
| L3 | Label key mismatch between CLI and dashboard (`corvia.spoke.name`) | SWE |
| L4 | Credential bind mount contradicts brainstorm warning | SWE |
| L5 | AGENTS.md mount may fail if workspace is on Docker volume | QA |
| L6 | Dashboard Docker dependency introduces new failure domain | QA |
| L7 | `spoke destroy --all` has no confirmation | QA, SWE |
| L8 | Agent ID collision on spoke reuse (spoke-42 v1 vs v2) | QA |
| L9 | macOS Docker Desktop / Codespaces portability | DevOps |
| L10 | Spoke image versioning and cache invalidation | DevOps |
| L11 | Container name collision across workspaces | DevOps |
| L12 | No log rotation for spoke containers | DevOps, PM |
| L13 | Spoke containers run as root | Security |
| L14 | No credential rotation/revocation mechanism | Security |

---

## Minor Issues (Nice to Have)

| # | Issue | Source |
|---|-------|--------|
| M1 | No spoke-level resource usage in dashboard (docker stats) | DevOps |
| M2 | Activity feed spoke detection uses string prefix, not lookup | SWE |
| M3 | Dashboard polls spokes every 5s, 15-30s is sufficient | PM, DevOps |
| M4 | No spoke restart command (preserve repo state) | PM |
| M5 | GitHub issue link hardcodes URL pattern | PM, QA |
| M6 | No rate limiting on MCP endpoint | Security |
| M7 | No content filter for secrets in corvia_write | Security |
| M8 | No audit log for spoke lifecycle events | Security |
| M9 | No spoke-level logging capture in corvia | SWE |
| M10 | Entrypoint no retry logic for transient git clone failures | QA |

---

## Consensus Strengths (All Reviewers Agree)

1. **Verified PoC before designing** - hands-on testing of auth, networking, MCP
2. **Knowledge-as-coordination** - right bet, avoids reinventing Claude Code teams
3. **Spokes-as-agents in dashboard** - no separate tab, enriches existing view
4. **Docker labels for state** - stateless, survives hub restarts
5. **MCP heartbeat over filesystem** - correct container-native abstraction
6. **Fresh clone over worktree** - evidence-driven pivot from empirical failure

---

## Recommended Fix Priority

### Phase 0 blockers (before any implementation)
- **I9**: Verify usage agreement with Anthropic
- **C7**: Design MCP auth token mechanism
- **I4**: Pin Claude Code version, never use `@latest`

### Phase 1 blockers (before spoke CLI ships)
- **C1**: HubContext error handling (no panics)
- **C2**: Duplicate spoke name guard
- **C5**: Container detection check
- **C6**: Network selection logic
- **C8**: Failure UX (prerequisite validation, startup health gate)
- **I1**: GITHUB_TOKEN validation
- **I2**: Default resource limits
- **I6**: Test plan
- **I7**: Startup error reporting
- **I10**: Branch naming strategy

### Phase 2 blockers (before dashboard ships)
- **L1**: Cache Docker client in AppState
- **L3**: Fix label key mismatch
- **L6**: Graceful Docker unavailability

### Phase 3 blockers (before autonomous spokes)
- **C3**: Credential expiry handling
- **C4**: Partial creation rollback
- **I3**: Agent identity auth tokens
- **I5**: Scoped GITHUB_TOKEN
- **I11**: Hub restart resilience
- **I13**: Spoke permission restrictions
- **L7**: Destroy --all confirmation
- **L13**: Non-root spoke containers
