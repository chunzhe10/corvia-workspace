# Portfolio Strategy for AI Engineer Job Hunt

Date: 2026-04-14
Context: Follow-up to harness-and-memory-landscape research. Owner is job-hunting as an AI engineer and needs to decide whether to continue corvia v2 work or pivot to portfolio-focused projects.

Companion doc: [2026-04-14-harness-and-memory-landscape.md](2026-04-14-harness-and-memory-landscape.md)

## 1. Strategic Reframe

Solo framework builders impress other solo framework builders. Shippers impress hiring managers. For a 1-3 month job hunt timeline, corvia v2's pluggable-backend architecture (Option B from the landscape doc) is the wrong bet — it's a 1-year project on a 3-month clock.

**Corvia v1 is already sufficient portfolio material.** The story "I built an MCP-native memory service from scratch in Rust because I wanted to understand the tradeoffs" is strong in interviews without requiring v2 completion. The job-hunt question is not "should I finish v2" but "what portfolio artifacts beyond corvia will land me a job."

## 2. What Hiring Managers Actually Want (2026)

Job descriptions for AI/ML/LLM engineer roles skew toward:

1. Production RAG — built it, shipped it, knows eval numbers
2. LangGraph / LangChain / LlamaIndex (but LangChain is contested — see notes)
3. Evals and observability — LangSmith, Langfuse, Braintrust, Arize
4. Vector DBs — Pinecone, Weaviate, pgvector, Qdrant (picked one, knows tradeoffs)
5. Cost/latency optimization — prompt caching, batching, model selection, quantization
6. Fine-tuning / distillation — LoRA, SFT, DPO basics
7. Deployment — FastAPI + Docker + cloud, basic MLOps
8. Multi-agent orchestration — CrewAI, AutoGen, OpenAI Agents SDK

**Not on the list:** "built my own memory framework from scratch." That's an architect signal, not an engineer-who-can-ship signal.

## 3. Why Generic RAG Projects Are Weak Signal

A generic "production-grade RAG app on LangChain" is bad portfolio advice in 2026:

- **Saturated market.** Every bootcamp grad ships a PDF Q&A bot. Signal has collapsed.
- **Redundant with corvia.** Corvia is already a RAG system; building a weaker second one is downgrading.
- **LangChain is contested.** Senior engineers often view LangChain PRs as neutral-to-negative due to API churn and spaghetti abstractions.
- **No users = no credibility.** A demo with fake queries proves you can follow a tutorial, not ship production software.
- **Frontier moved.** Pure RAG is table stakes; agents, evals, memory, and cost/latency are where attention is.

**Unifying principle:** projects that produce numbers and have users beat projects that produce demos.

## 4. Three Viable Paths

### Path 1: Memory Systems Eval Harness

Build a public, reproducible benchmark comparing Mem0, Zep CE, Letta, LangMem, and corvia on LongMemEval plus 1-2 domain tasks.

**Why strong:**
- No good neutral comparison exists (vendor numbers only)
- Publishable: blog post + GitHub + HN submission
- Positions candidate as memory specialist
- Solves corvia's benchmarking gap as a side effect
- Evals is a hot JD keyword
- 4-6 weeks scoped work
- Defensible in interviews with real data

**Acceptance criteria:**
- Reproducible `make bench` across all systems
- Blog post with methodology and honest failure modes
- Docker-compose for reproduction
- Langfuse/Braintrust traces wired up
- Cost-per-interaction alongside accuracy
- At least one finding that contradicts vendor marketing

#### Cost analysis

LongMemEval-S: ~500 instances, ~50 turns each. Per system full run:

| Component | Model | Cost per system |
|---|---|---|
| Ingestion (fact extraction) | Haiku / GPT-4o-mini | ~$5-15 |
| Retrieval | Embeddings only | ~$1-3 |
| Answer generation | Sonnet / GPT-4o | ~$15-30 |
| LLM-as-judge | Opus / GPT-4 | ~$20-40 |
| **Per-system total** | | **~$40-90** |

Five systems × ~$65 average = **$325**. With iteration debugging: **$500-800** realistic budget.

LongMemEval-M is 3-5x more expensive. LongMemEval-L is 10x. Skip both for v1.

#### Free-tier paths

- **Groq** — free tier with generous rate limits. Llama 3.3 70B, Llama 3.1 8B
- **Google AI Studio (Gemini 2.0 Flash)** — 1500 requests/day free
- **Together AI** — $25 signup credit
- **OpenRouter** — limited free tier
- **Local inference** — corvia-inference already runs ONNX, llama.cpp/Ollama free for small LLMs
- **Mem0 Cloud, Zep Cloud** — free tiers (check current limits)
- **Letta, LangMem, Zep CE** — fully self-hostable free

**Shoestring path ($0-50):** local embeddings, Gemini free tier for answers, Groq for extraction, paid judge on a 50-100 case subset. Defensible with "subset of LongMemEval-S" caveat.

**Mid-tier path ($200-400):** free tiers where possible, real money for judge, full 500-instance LongMemEval-S. Sweet spot.

**Research credits:** Anthropic, OpenAI, Google all have research credit programs. "Building open memory benchmarks" is a legitimate pitch.

**Recommendation:** start shoestring, harden harness with 20-50 cases, then decide between self-funding or applying for research credits for full run.

### Path 2: Narrow Vertical Agent Using Corvia

Build an agent that solves one specific problem for a real micro-audience. 3-4 weeks, ship to 10-50 real users.

**Candidates:**
- **Job-hunt agent** (dogfood): scrapes JDs, semantic-matches against resume, drafts cover letters, tracks applications. Uses corvia as memory. User benefits directly.
- **Research assistant** for a specific domain
- **Code review agent** for a specific framework

**Job-hunt agent build options:**

**Option A — Deployed service with Anthropic API:**
- `anthropic` Python SDK, or LangGraph, or Anthropic Managed Agents API, or Pydantic-AI
- Sonnet 4.6 reasoning, Haiku 4.5 cheap summarization
- Prompt caching (up to 90% savings on cached tokens)
- Deploy Fly.io / Railway / Render
- Estimated cost: $1-5/day for personal use

**Option B — Inside Claude Code as MCP tools + superpowers skill:**
- MCP tools: `fetch_jd`, `extract_requirements`, `score_match`, `draft_cover_letter`, `track_application`
- Storage: corvia (perfect dogfood)
- Workflow: skill in `.claude/skills/job-hunt/`
- Invoked as `/job-hunt <url>`
- Runs inside Claude Code on Max subscription quota
- **Zero marginal API cost** during development

**Option B is the pick.** Teaches MCP tool authoring (hireable skill), zero cost, dogfoods corvia, directly useful for the user's own job hunt.

**Learning-tool framing alternatives:**
- "Explain this paper" agent that remembers prior reading
- Spaced-repetition interview prep agent
- Code-reading companion with persistent context

### Path 3: OSS Contributions

Merge 3-5 substantive PRs into a known project. Fastest credibility-per-hour on a resume.

**Ranking criteria:** community size, feature impact, market appreciation, contribution barrier.

| Project | Stars | Activity | Impact | Market signal | Barrier |
|---|---|---|---|---|---|
| **Mem0** | 48K | Very high | High | Very high | Medium |
| **Letta (MemGPT)** | 17K | High | High | High | Medium-high |
| **LangGraph** | 13K | Very high | High | High | Medium |
| **MCP Python/TS SDK** | ~10K | Very high | Very high | Very high | Low-medium |
| **MCP Rust SDK** | 3.3K | Very high | Very high | Very high | Low for this candidate |
| **sst/opencode** | ~140K claimed | Very high | High | Medium | Medium |
| **Qdrant** | 22K | High | Medium | Medium-high | High |
| **llama.cpp** | 80K+ | Very high | Very high | Medium | Very high |
| **vLLM** | 35K | Very high | Very high | High | Very high |

**Top pick: MCP Rust SDK** (see Section 5 — this became the clear winner once Rust experience was factored in).

**Avoid:**
- llama.cpp / vLLM — crowded with systems experts, invisible unless kernel-level
- LangChain core — churn + ambiguous signal
- Documentation-only PRs — heavily discounted

## 5. MCP Rust SDK Deep Dive

**Repo:** [github.com/modelcontextprotocol/rust-sdk](https://github.com/modelcontextprotocol/rust-sdk)

**Stats (as of 2026-04-14):**
- 3.3K stars, 497 forks
- 16 open issues, 66 open PRs
- Official Anthropic-blessed
- Rust edition 2024, tokio async
- `rmcp` + `rmcp-macros` workspace, v0.12.0
- Published to crates.io with release-plz automation

**Why this is the best fit for this candidate specifically:**

Corvia is already a Rust MCP server in production. That means the candidate has hit every pain point the SDK is trying to solve:

1. Transport implementation details (stdio, SSE, HTTP, WebSocket edge cases)
2. Schema generation and JSONSchema gotchas
3. Async cancellation and backpressure under disconnect
4. Error propagation (protocol vs tool vs transport)
5. Streaming responses for large tool results
6. Auth and session handling
7. Cross-SDK interop (Rust server vs Python/TS clients)

Most SDK contributors contribute from the library-author perspective. Corvia experience brings the **"used this in anger in production"** lens, which is rarer and more valuable.

**Why it beats Python/TS SDK:**

| Factor | Rust SDK | Python/TS SDK |
|---|---|---|
| Existing expertise | Direct (corvia) | Indirect |
| Contributor pool | Smaller, high-signal | Larger, noisier |
| Issue backlog | Active but tractable | Large, many trivial |
| Visibility per PR | High | Medium |
| Matches corvia v2 story | Directly | Indirectly |

### Entry plan

**Week 1: Reconnaissance**
1. Clone, read README + CONTRIBUTING, skim recent merged PRs for review style
2. Build locally, run test suite
3. Run examples/servers against Claude Code MCP client
4. Compare SDK implementation against corvia's MCP layer — divergences are potential learnings or bugs
5. Read `good-first-issue`, `help-wanted`, `bug` labels, shortlist 3-5 tractable issues
6. Budget max 2-3 hours on reconnaissance

**Week 2: First PR (small but substantive)**

Good first-PR shapes:
- Bug fix with reproducing test (highest signal)
- Missing example (e.g., server using specific transport)
- Rustdoc gap (only if substantive)
- Test coverage for specific code path
- Small ergonomic improvement with benchmark

Target: merged within 2 weeks.

**Weeks 3-6: Larger contribution**

Once maintainers recognize the contributor, pick something meatier:
- New transport if any are missing
- Performance work with benchmarks
- New MCP spec feature implementation (huge credibility move)
- Interop tests across SDKs

**Weeks 6-10: Blog post**

"What I learned building corvia, an MCP server in Rust, and contributing to the official Rust SDK."

Cover:
- Why Rust for corvia
- Three protocol edge cases hit in production
- What the SDK does well and what could improve (constructive)
- Contributions and what they taught about the protocol

Lands on HN, gets shared by Anthropic folks, linked in every interview conversation.

### Career compound effect

- **Interview dynamic shifts** from "tell me about a project" to "I saw your PRs, let's discuss transport design." Recruited, not screened.
- **Anthropic, Cursor, Sourcegraph, every MCP-building company** notices the contributor list
- **Protocol is foundational and young** — early contributors become de facto experts. LSP, gRPC, GraphQL early contributors all got great jobs off the identity.
- **Corvia becomes much stronger** framed as "I built this, then contributed back to the upstream SDK"

### Caveats

- First PR always takes longer than expected (learning review culture)
- Accept reviewer feedback quickly, don't argue nits
- Cultural fit matters as much as code quality in OSS

## 6. Recommended Sequence (6-10 Weeks)

| Weeks | Action |
|---|---|
| 1-2 | MCP Rust SDK reconnaissance + first small PR |
| 2-6 | Eval harness shoestring build (Path 1), publish partial results |
| 5-8 | Job-hunt agent as MCP tools + superpowers skill (Path 2), dogfood during real hunt |
| 6-10 | Second MCP SDK PR (larger), finish eval harness full run if credits obtained |
| 10+ | Blog posts, interviews |

Three artifacts tied together by one theme (MCP-native memory + agents), grounded in real numbers and real usage.

## 7. What to Stop Doing

- **Corvia v2 feature work beyond the minimum needed for the eval harness.** Revisit after landing a job.
- **Generic demo projects** with fake users.
- **LangChain-first learning** unless a specific JD demands it.
- **Reading more about the landscape.** Research is done. Execute.

## 8. Key Strategic Insights

1. **Portfolio strategy ≠ product strategy.** Corvia v2 (Option B) may be the right product bet on a 1-year timeline. It is not the right portfolio bet on a 3-month timeline.
2. **Corvia v1 is already enough** as a portfolio anchor. Don't gate job hunting on finishing v2.
3. **Numbers and users beat demos.** Every chosen path must produce one or both.
4. **MCP Rust SDK is unusually well-aligned.** Rare intersection of existing expertise, high visibility, and strong market signal.
5. **The three paths compound.** Eval harness validates corvia, job-hunt agent dogfoods corvia, SDK contributions establish MCP credibility. All three reinforce the same identity: "MCP-native memory and agents expert."
6. **Time pressure changes the math.** Ambitious framework projects are for employed people building on nights/weekends. Focused portfolio projects are for the unemployed.

## Sources

- [Mem0 + Zep + LangChain integration patterns](https://dev.to/anajuliabit/mem0-vs-zep-vs-langmem-vs-memoclaw-ai-agent-memory-comparison-2026-1l1k)
- [Zep LangChain integration docs](https://docs.getzep.com/sdk/langchain/)
- [Edge AI Dominance 2026](https://medium.com/@vygha812/edge-ai-dominance-in-2026-when-80-of-inference-happens-locally-99ebf486ca0a)
- [On-Device LLMs 2026](https://www.edge-ai-vision.com/2026/01/on-device-llms-in-2026-what-changed-what-matters-whats-next/)
- [modelcontextprotocol/rust-sdk](https://github.com/modelcontextprotocol/rust-sdk)
- [Rust SDK examples](https://github.com/modelcontextprotocol/rust-sdk/tree/main/examples)
- [Rust SDK open PRs](https://github.com/modelcontextprotocol/rust-sdk/pulls)
