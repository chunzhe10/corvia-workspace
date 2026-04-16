# Re-eval: Malaysia Market Signal — "Agents From Scratch" and Harness Building

Date: 2026-04-15
Context: Interviewers in Malaysia are consistently asking "what agents have you built?" The read is that local hiring managers want engineers who can build both the harness (orchestration loop) and an agent on top of it from scratch, not just integrate a framework. Re-evaluating whether the current portfolio plan produces that signal.

Companion docs:
- [2026-04-14-harness-and-memory-landscape.md](2026-04-14-harness-and-memory-landscape.md)
- [2026-04-14-portfolio-strategy-ai-engineer.md](2026-04-14-portfolio-strategy-ai-engineer.md)
- [2026-04-15-mcp-vs-mem0-reconciliation.md](2026-04-15-mcp-vs-mem0-reconciliation.md)

## 1. The Signal Decoded

"What agents have you built" in the Malaysia market almost never means "what LangChain chains did you wire up." Based on JD scraping and recruiter conversations, the unstated rubric is:

1. **You wrote the loop.** Tool dispatch, multi-step reasoning, state transitions, error recovery — not hidden behind a framework abstraction.
2. **You understand the primitives.** Messages array, tool schemas, stop reasons, token accounting, retries, streaming.
3. **You shipped an end-to-end artifact.** A thing that runs, that someone (even you) uses, with a visible demo.
4. **You can speak to tradeoffs.** Why raw SDK here, why LangGraph there, why MCP vs custom tool format, why this model for this step.

"Built a harness" in the same conversation means the orchestration layer itself: the thing Claude Code, Cursor, Aider, and Devin are. Session state, tool execution sandbox, checkpointing, context management, hook system. Most candidates have never touched this layer.

Malaysia hiring is 6-12 months behind SF on framework fatigue. LangChain on the resume still scores, but a candidate who can demonstrate the layer *under* LangChain scores higher — and is rare locally.

## 2. Gap Analysis vs Current Plan

The [portfolio strategy doc](2026-04-14-portfolio-strategy-ai-engineer.md) recommends three tracks: MCP Rust SDK PRs, memory eval harness, job-hunt agent (as MCP tools inside Claude Code).

Against the Malaysia rubric:

| Rubric criterion | Corvia v1 | MCP Rust SDK PRs | Memory eval harness | Job-hunt agent (Option B) |
|---|---|---|---|---|
| Wrote the agent loop | No (it is memory infra) | No (library work) | No (eval harness is not an agent) | **No — Claude Code is the harness** |
| Primitives fluency | Indirect (server side) | Yes (protocol layer) | Partial | Partial |
| Shipped end-to-end agent | No | No | No | Partial — runs inside Claude Code |
| Tradeoff narrative | Strong (memory) | Strong (protocol) | Strong (evals) | Weak (no "I built the loop" story) |

**The gap is real.** Nothing in the current plan produces an agent where the candidate wrote the loop. Option B of the job-hunt agent intentionally outsources the loop to Claude Code — which is efficient for dogfooding but blunts the Malaysia interview answer. The interviewer asks "what agent have you built" and the honest answer is "a set of MCP tools that run inside someone else's harness." That is accurate but loses the room.

Corvia does not close the gap. Corvia is infrastructure — a memory server. It is an *excellent* story for a senior/staff interview focused on systems depth, but it does not answer "what agents have you built" directly.

## 3. Proposed Adjustment

Elevate agent-building from a side-effect of the job-hunt agent track to a primary deliverable. Two concrete additions to the plan, both scoped tight:

### Addition A: A minimal agent harness, in public

Build a small, documented, open-source agent harness from scratch. Not a framework competitor — a pedagogical-quality reference implementation the candidate controls end to end.

**Scope (must-haves):**
- Raw Anthropic SDK (no LangGraph, no LangChain, no Pydantic-AI)
- Custom message/tool loop with explicit stop-reason handling
- Tool registry with JSONSchema validation
- MCP client built in — can consume any MCP server including corvia
- Session state persisted to disk (JSON, not a DB)
- Streaming output with basic UI (TUI or simple web)
- Structured logs of every LLM call, tool call, and decision
- Prompt caching wired up from day one
- Token budgets and a compaction hook

**Explicit non-goals:**
- Multi-agent orchestration (defer)
- Graph-based workflow DSL (that is LangGraph's job)
- Plugin/skill system
- Replacing Claude Code

**Name it something honest.** "miniharness" or "looproom" or similar — signals "I built this to learn and teach, not to compete with CrewAI." Framework-pretenders get dismissed; learning artifacts get respected.

**Time budget:** 2-3 weeks for v0.1 (works end-to-end with one tool), then iterate.

### Addition B: An agent *built on that harness*, not on Claude Code

Rebuild the job-hunt agent (or pick a different narrow vertical) on top of the custom harness instead of as Claude Code MCP tools.

**Why the rebuild matters:**
- Interviewer asks "show me an agent you built." Candidate opens a terminal, runs `./looproom job-hunt https://...`, and an agent the candidate wrote end to end executes a real task.
- The demo implicitly proves the harness works.
- Corvia still appears — as the agent's memory backend, accessed over MCP from the custom harness. All three components (harness, agent, memory) are the candidate's work.

**This replaces Option B of the original plan** (MCP tools in Claude Code) as the primary agent deliverable. Option B stays as a secondary artifact if time permits — it dogfoods nicely and costs nothing.

## 4. How This Interacts With the Existing Three Tracks

The additions do not displace the existing tracks — they re-sequence them:

| Weeks | Revised action |
|---|---|
| 1-2 | Harness v0.1 — raw SDK loop, one tool, streaming, session log. Public repo from day one. |
| 2-3 | Harness v0.2 — MCP client, corvia integration, prompt caching, compaction hook |
| 3-5 | Job-hunt agent built on harness. Real usage during real job hunt. |
| 4-7 | Memory eval harness (Path 1 from original doc) — now benefits from the custom harness as a neutral test client |
| 5-9 | MCP Rust SDK first PR, then larger contribution |
| 8-10 | Blog posts: "Building an agent harness from scratch in a weekend (and the next three weeks fixing it)", "Benchmarking memory systems with a harness I control", "What production MCP taught me about the Rust SDK" |

Three blog posts, three artifacts, one identity: **engineer who builds both the harness and the agent, and has opinions backed by numbers.**

## 5. Why This Is Not Scope Creep

Concern: adding a harness to the plan looks like exactly the kind of ambitious side project the original strategy doc warned against. Three reasons it is not:

1. **Scope is bounded by the rubric, not by feature completeness.** The harness only needs to demonstrate the primitives, not compete with LangGraph. v0.1 is "loop + one tool + session log." That is a weekend, not a quarter.
2. **It unblocks the other tracks.** The memory eval harness needs an agent-like test client anyway. Building it once as a reusable harness is cheaper than building an ad-hoc client per benchmark.
3. **It directly answers the most-asked interview question.** No other item on the portfolio does. The ROI per week of effort is the highest of any track.

The original doc's warning was against *framework* projects — pluggable-backend, 1-year scope, solo-competitor-to-Mem0 energy. A pedagogical harness with explicit non-goals is a different shape of project.

## 6. Risks and Counterarguments

**"A hand-rolled harness looks junior compared to contributing to LangGraph."** True in SF. Less true in KL/PJ, where local senior engineers are often skeptical of LangChain-family abstractions and reward candidates who can demonstrate the layer below. The harness is *also* great SF material because it signals "understands the primitives" — the framing is what changes, not the artifact.

**"Claude Code already is the harness, just use it."** That is the efficient answer for personal productivity. It is the wrong answer for the portfolio narrative. The interview question is "what have you built," and "I used Claude Code well" is not a building answer.

**"Three weeks of harness work is three weeks not spent on MCP SDK PRs or the eval harness."** Correct, and acknowledged. The sequencing above front-loads the harness because it unblocks both other tracks. If the harness slips past week 3, cut it to v0.1-only and move on — it is allowed to be unfinished as long as the loop works end to end.

**"What if the interviewer actually wanted to hear about LangChain?"** Then answer with the harness first ("here's the loop I wrote") and pivot to "and here's the LangGraph version for comparison, which is the second half of the blog post." The harness answer dominates every framework answer; a framework answer does not dominate the harness answer.

## 7. Revised Identity Statement

Original (from reconciliation doc):
> "I built corvia, a local-first Rust MCP memory server. Benchmarked it against Mem0, Zep, and Letta. Contributed to the MCP Rust SDK."

Revised:
> "I built an agent harness from scratch in Python to understand the primitives, then built a job-hunt agent on top of it that I actually use. For the memory layer I use corvia, a Rust MCP server I also wrote — benchmarked against Mem0, Zep, and Letta on LongMemEval, with the numbers published. I contribute to the MCP Rust SDK to stay close to the protocol layer."

Same 40-45 seconds. Now it answers the "what agents have you built" question in the first sentence, which is what the Malaysia market is asking for.

## 8. Action Items

1. **This week:** create a new repo, `looproom` (or agreed name), commit an empty README with the non-goals list. Signals public intent.
2. **Weeks 1-2:** harness v0.1 — raw SDK, one tool (a `shell` or `http_get`), streaming, session log, prompt caching. Ship to GitHub with demo gif.
3. **Weeks 2-3:** MCP client in the harness; first external MCP server consumed is corvia. Blog draft started.
4. **Weeks 3-5:** rebuild the job-hunt agent on the harness. Dogfood during actual applications.
5. **Revisit in 3 weeks:** if v0.1 shipped and the job-hunt agent runs end to end, continue to the original tracks (eval harness, MCP SDK PRs). If v0.1 slipped, cut scope further — the loop itself is the non-negotiable deliverable.
6. **Do not delete the original plan.** The MCP SDK and memory eval harness tracks remain valid; they are re-sequenced, not replaced.

## 9. Key Strategic Insights (Delta from Prior Docs)

1. **The Malaysia rubric is loop-centric, not framework-centric.** Candidates who show the loop they wrote beat candidates who show the framework they wired.
2. **Corvia alone does not answer "what agents have you built."** It is infrastructure. An agent artifact is required alongside it.
3. **A minimal harness is cheap insurance.** 2-3 weeks to dominate the single most-asked interview question is the best marginal spend available.
4. **The harness compounds with existing tracks.** It becomes the eval-harness test client, the MCP SDK integration test bench, and the demo surface for corvia.
5. **Scope discipline is the whole game.** The harness must stay pedagogical. The moment it grows a plugin system or a workflow DSL, it becomes the 1-year framework project the original strategy warned against.

## Sources

Internal only — this doc is a re-evaluation of prior research triggered by a market signal, not a new external-research pass. For the underlying landscape data, see the companion docs listed above.
