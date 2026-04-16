# Harness and Memory Landscape

Date: 2026-04-14
Context: Research triggered by questions about opencode, Claude Max subscription policy, and how corvia fits into the broader AI agent ecosystem.

## 1. Anthropic's Third-Party Harness Policy (April 4, 2026)

Effective 2026-04-04, Anthropic blocked Claude Pro/Max OAuth tokens from being used in third-party harnesses. The updated ToS explicitly prohibits using subscription-derived OAuth tokens "in any other product, tool, or service."

Affected tools include opencode, OpenClaw, and similar third-party harnesses. Claude Code itself (Anthropic's own harness) is unaffected.

### User options

1. Use an API key (pay-as-you-go billing, separate from subscription)
2. Purchase extra usage bundles via Claude account page (Anthropic offered 30% off transition pricing plus a one-time credit equal to one month of subscription, redeemable through 2026-04-17)

### Rationale (per Boris Cherny, Head of Claude Code)

- "Our subscriptions weren't built for the usage patterns of these third-party tools"
- "Capacity is a resource we manage thoughtfully and we are prioritizing our customers using our products and API"
- Reports of $200/mo Max subscriptions running $1,000-$5,000 worth of agent compute

### Timeline

- 2026-01-09: First block of subscription OAuth tokens outside official apps. No advance notice. Reversed after community backlash.
- 2026-02: Terms of Service revised to formally prohibit third-party harness usage.
- 2026-04-03 evening: Public announcement via X
- 2026-04-04 12:00 PM PT: Cutoff went live

### Sources

- [TechCrunch coverage](https://techcrunch.com/2026/04/04/anthropic-says-claude-code-subscribers-will-need-to-pay-extra-for-openclaw-support/)
- [The Register](https://www.theregister.com/2026/04/06/anthropic_closes_door_on_subscription/)
- [VentureBeat](https://venturebeat.com/technology/anthropic-cuts-off-the-ability-to-use-claude-subscriptions-with-openclaw-and)
- [Did Anthropic Just Kill OpenCode? - Rida Kaddir](https://ridakaddir.com/blog/post/did-anthropic-kill-opencode-claude-subscription-ban)

## 2. What is a Harness?

A harness is the program that wraps an LLM and turns it into an agent. The LLM alone takes text in and produces text out. The harness is everything around it that makes the model act.

### What a harness does

1. Runs the agent loop (call model → parse → execute tool calls → feed results back → repeat)
2. Defines and executes tools (Read, Bash, Edit, MCP tools)
3. Manages the context window (system prompts, file contents, history, compaction)
4. Handles human I/O (TUI, streaming, interrupts, permissions)
5. Enforces safety (sandboxing, permission modes, hook execution)

### Model vs harness

- Model = brain
- Harness = body

Same underlying LLM behaves wildly differently depending on the harness around it.

## 3. Coding Harness Landscape

| Harness | Vendor | Model lock-in |
|---|---|---|
| Claude Code | Anthropic | Claude only |
| Antigravity | Google | Gemini only |
| Codex CLI | OpenAI | GPT only |
| Cursor | Cursor Inc. | Model-flexible |
| Windsurf | Codeium | Model-flexible |
| opencode | SST | Model-flexible (75+ models) |
| Aider | Paul Gauthier | Model-flexible |

### Structural observation

Every major lab ships a first-party harness (Claude Code, Antigravity, Codex) to control the end-to-end experience and keep users on their models. A second tier of model-agnostic harnesses (Cursor, opencode, Aider) competes on flexibility and openness.

Harnesses are converging on similar feature sets (TUI/IDE, tool calling, MCP, skills, AGENTS.md) and becoming commoditized. The "harness wars" are really a distribution fight over who owns the developer's terminal, not a fight over fundamentally different capabilities.

### What doesn't commoditize

1. The model (lab moat)
2. Persistent memory / knowledge
3. Domain-specific workflows (vertical agents)

## 4. OpenCode Deep Dive

- Repo: [github.com/sst/opencode](https://github.com/sst/opencode)
- Site: [opencode.ai](https://opencode.ai)
- Built by SST team in Go, released late 2025
- Terminal TUI, also IDE extension and desktop app
- 140K+ GitHub stars, 850 contributors, claims 6.5M monthly developers

### Context/memory story

Three layers:

1. **Procedural**: `AGENTS.md` files, loaded every session. Concatenated into context, no retrieval.
2. **Episodic**: Built-in session history + auto-compaction. Single conversation only. Does not persist across sessions.
3. **Skills**: Native `skill` tool that lazy-loads `SKILL.md` files on demand from `~/.config/opencode/skills/` or `.opencode/skills/`. Discovered at startup, cached. Requires restart to pick up new skills.

No built-in RAG or long-term cross-session memory. That gap is left to plugins.

### Community plugins for memory

- [opencode-agent-memory](https://github.com/joshuadavidthomas/opencode-agent-memory) — Letta-inspired memory blocks
- [Hmem](https://news.ycombinator.com/item?id=47103237) — Hierarchical memory via MCP

### Superpowers integration

Obra has ported superpowers to opencode: [Superpowers for OpenCode](https://blog.fsck.com/2025/11/24/Superpowers-for-OpenCode/). Same skills work in both harnesses.

### Sources

- [OpenCode docs](https://opencode.ai/docs/)
- [OpenCode Rules / AGENTS.md](https://opencode.ai/docs/rules/)
- [OpenCode Skills](https://opencode.ai/docs/skills/)
- [OpenCode Plugins](https://opencode.ai/docs/plugins/)

## 5. Coding Harness vs Production Agent Runtime

Coding harnesses and production agents share three primitives (model + loop + tools) but invert most priorities.

| Dimension | Coding harness | Production agent runtime |
|---|---|---|
| User | Developer, interactive | End user or upstream system, often async |
| Session | One at a time, TUI-bound | Thousands concurrent, stateless workers |
| Tools | Generic (Read/Bash/Edit) | Narrow, domain-specific (Zendesk, CRM, SQL) |
| Loop | Human approves steps | Fully autonomous, long-running |
| Memory | Session + AGENTS.md | Per-user, per-thread, cross-session, durable |
| Failure handling | Human retries | Retries, DLQs, fallbacks, human escalation |
| Observability | Terminal output | Traces, metrics, cost/latency SLOs |
| Deploy | Local binary | Containers, autoscaling, multi-tenant |

### Production agent examples

- **Autonomous coding**: Devin (Cognition), SWE-agent
- **Customer support**: Sierra, Decagon, Ada
- **Research**: Perplexity, Exa agents
- **Vertical legal**: Harvey, EvenUp
- **Voice**: Vapi, Retell, Bland

### Production agent frameworks

LangGraph, Pydantic-AI, Mastra, CrewAI, OpenAI Agents SDK, Anthropic Managed Agents API. These provide loop machinery so builders focus on tools and behavior.

### What production agents care about that coding harnesses ignore

1. Multi-tenant memory isolation (user A's context must never leak to user B)
2. Guardrails (input validation, output filtering, PII scrubbing, tool allowlists per user)
3. Evaluation harnesses (offline test suites, regression catching)
4. Cost per interaction (a $0.50 conversation doesn't ship)
5. Latency budgets (users won't wait 40s for a reply)
6. Traces as first-class (LangSmith, Langfuse, Braintrust, Arize)

## 6. Agent Memory Taxonomy (Industry Standard)

The field has converged on four memory types from the CoALA framework (Princeton 2023):

1. **Working memory** — the current context window (volatile, session-scoped)
2. **Procedural memory** — system prompts, rules, tool definitions (AGENTS.md lives here)
3. **Semantic memory** — facts, preferences, entity knowledge ("user prefers Rust, works in fintech")
4. **Episodic memory** — timestamped events ("last Tuesday deploy failed due to missing env var")

Every serious memory system implements some subset. This is the closest thing to an industry standard.

### Programmatic vs agentic memory

- **Programmatic**: developer defines what gets stored and retrieved
- **Agentic**: the agent itself decides what to remember, update, forget via tool calls

Letta and LangMem support both patterns.

## 7. Memory Framework Landscape (2026)

| Product | Architecture | Shape | Target |
|---|---|---|---|
| **Mem0** | Vector-based, LLM extracts facts | Memory-as-library, bolted onto any framework | Chatbots, personal assistants. 48K GitHub stars |
| **Zep** (Graphiti) | Temporal knowledge graph (vector + graph) | Managed service, tracks how facts change over time | Long-running agents. Best LongMemEval score |
| **Letta** (formerly MemGPT) | Tiered OS-inspired: message buffer → core blocks → archival | Full agent runtime | Complex agents where memory is the product |
| **LangMem** | SDK inside LangChain/LangGraph | Programmatic + agentic, framework-coupled | LangChain teams |
| **Supermemory, Cognee, ODEI** | Various | Newer entrants | Niche positioning |

### Benchmark data (LongMemEval)

- Zep: 63.8%
- Mem0: 49.0%

15-point gap attributed to Zep's temporal knowledge graph architecture.

### Retrieval speed

- Some systems: sub-300ms
- Zep: ~4s
- Mem0: 7-8s

### Two architectural camps

1. **Memory-as-a-service** (Mem0, Zep, Supermemory, corvia): clean API boundary, bolt onto any framework, minimal lock-in. Swap memory, keep orchestrator.
2. **Memory-as-runtime** (Letta): agents live inside the runtime. Memory is first-class but adoption requires rewriting agents. High lock-in, high ceiling.

### Sources

- [Best AI Agent Memory Frameworks 2026 - Atlan](https://atlan.com/know/best-ai-agent-memory-frameworks-2026/)
- [5 AI Agent Memory Systems Compared](https://dev.to/varun_pratapbhardwaj_b13/5-ai-agent-memory-systems-compared-mem0-zep-letta-supermemory-superlocalmemory-2026-benchmark-59p3)
- [Mem0 vs Letta - Vectorize](https://vectorize.io/articles/mem0-vs-letta)
- [Graph Memory Solutions Compared - Mem0 blog](https://mem0.ai/blog/graph-memory-solutions-ai-agents)
- [Agent Memory - Letta blog](https://www.letta.com/blog/agent-memory)
- [Memory Systems for AI Agents - Steve Kinney](https://stevekinney.com/writing/agent-memory-systems)
- [MemGPT research](https://research.memgpt.ai/)

## 8. Where Corvia Fits

Architecturally corvia sits in the memory-as-a-service camp alongside Mem0, Zep, and Supermemory. MCP-first boundary is genuinely differentiated — none of the leading competitors lead with MCP.

### Strengths vs competitors

- **MCP-first**: works with any harness or runtime speaking MCP (Claude Code, opencode, Cursor, custom production agents). Mem0 and Zep don't lead with MCP.
- **Local-first posture** (v2 pivot): unusual in the space. Competitors are all cloud-managed. Matters for regulated industries and developer trust.
- **Git-synced**: also unusual. Enables review workflows and audit trails.
- **Scope-based multi-tenancy**: `scope_id` primitive already in place.
- **Agent identity tracking + supersession history**: covers episodic and semantic layers.

### Gaps

1. **Temporal knowledge graph**: Zep's Graphiti is genuinely ahead on temporal reasoning. Corvia has history but not a temporal graph. Zep's 15-point LongMemEval lead comes from this.
2. **Benchmarks**: Zep and Mem0 publish LongMemEval numbers. Corvia doesn't. Memory notes already flag benchmarking as v2's key differentiator — without numbers, positioning is soft.
3. **Evals integration**: no hooks into Langfuse, LangSmith, Braintrust yet.
4. **SDK surface friction**: Mem0 has `from mem0 import Memory` one-liner adoption. Corvia's MCP-first path is architecturally purer but higher adoption friction for Python-native teams.

### Strategic question (unresolved)

Who is corvia v2 for?

- **Developers using coding harnesses**: local-first/git-synced is the killer feature. Smaller TAM, less contested but harder to monetize.
- **Production agent builders**: need benchmarks, SDKs, observability integrations. Local-first is neutral-to-negative here. Larger TAM, more fragmented, but crowded.
- **Both**: possible, but risks being mediocre at each.

Current v2 scope docs lean toward the first group (developer tooling). Production agent builders would pull the roadmap toward benchmarks and SDKs instead of git-sync and local-first.

This question is worth a dedicated brainstorming session before v2 implementation goes much further.

## 9. Key Takeaways

1. **Harnesses are commoditizing.** Claude Code, Antigravity, Cursor, opencode all look structurally similar. Moat is shifting to models and memory.
2. **MCP is the unification layer.** Harnesses already converge on it. Corvia's MCP-first bet is structurally sound.
3. **Memory has an industry-standard taxonomy** (working / procedural / semantic / episodic). Corvia already implements semantic + episodic; should explicitly map to this vocabulary.
4. **Corvia's differentiation is real but unproven.** Local-first + git-synced + MCP-first has no direct competitor. But without benchmarks and clear target buyer, it reads as "interesting" rather than "required."
5. **Anthropic's third-party harness ban reinforces the v2 strategy.** It validates that harnesses are increasingly siloed while memory wants to be portable.
