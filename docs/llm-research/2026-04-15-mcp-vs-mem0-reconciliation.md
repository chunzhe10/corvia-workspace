# MCP vs Mem0: Reconciling the Portfolio Bet

Date: 2026-04-15
Context: Follow-up concern that MCP might be phasing out and Mem0 might be the better portfolio bet. Checked the data. Both are growing. They're different layers of the stack, not competitors.

Companion docs:
- [2026-04-14-harness-and-memory-landscape.md](2026-04-14-harness-and-memory-landscape.md)
- [2026-04-14-portfolio-strategy-ai-engineer.md](2026-04-14-portfolio-strategy-ai-engineer.md)

## 1. MCP Status (as of April 2026)

**Not phasing out. Fastest-adopted AI infra standard in history.**

- **97 million SDK installs** as of 2026-03-25
- **10,000+ active public MCP servers**
- **OpenAI** adopted it in March 2025 across Agents SDK, Responses API, ChatGPT desktop
- **Google DeepMind** confirmed MCP support in Gemini (April 2025)
- **Microsoft** integrated it into Windows, Foundry, Azure
- **AWS, Cloudflare, Bloomberg, Block** participating in ecosystem
- **Donated by Anthropic to the Linux Foundation** under the Agentic AI Foundation (AAIF)

### Why the donation matters

Foundation governance is a strong durability signal. Donation + multi-vendor governance means MCP survives even if Anthropic's priorities change. This is the pattern of protocols that become durable standards (LSP, gRPC, OpenTelemetry) rather than dying in year 1.

### Four signals to watch for protocol durability

1. **Governance diversification** — did it move beyond one vendor? **MCP: yes, Linux Foundation.**
2. **Multi-lab adoption** — are competitors using it? **MCP: yes, OpenAI, Google, Microsoft, AWS.**
3. **Ecosystem density** — are there many servers/clients? **MCP: 10,000+ public servers.**
4. **Spec stability** — are breaking changes slowing? **MCP: yes, stable spec cadence.**

All four positive. Protocols that get phased out typically fail signals 1 or 2 within 12 months. MCP cleared both.

## 2. Mem0 Status (as of April 2026)

**Also legitimately hot. Different layer, not a substitute.**

- **$24M Series A** in Oct 2025, led by Basis Set Ventures, with YC, Peak XV, GitHub Fund, Kindred
- **41K GitHub stars, 13M Python package downloads**
- **186M API calls in Q3 2025** (up from 35M in Q1 — ~30% MoM growth)
- **80K cloud signups**
- **AWS selected Mem0 as exclusive memory provider for AWS Agent SDK** — major distribution win
- Native integrations in CrewAI, Flowise, Langflow
- Thousands of production users from startups to Fortune 500

## 3. The Reconciliation

**Key insight: MCP and Mem0 are not in the same category.** They operate at different layers of the agent stack.

| Layer | What it is | Examples |
|---|---|---|
| **Protocol** | How agents talk to tools and memory | MCP, A2A, OpenAI Function Calling |
| **Framework/Runtime** | Agent loop + orchestration | LangGraph, Letta, OpenAI Agents SDK |
| **Memory product** | Storage + retrieval | Mem0, Zep, Letta, corvia |
| **Model** | LLM itself | Claude, GPT, Gemini |

Mem0 can — and will — expose itself over MCP. As MCP becomes the default tool interface, Mem0 deployments become MCP-accessible by default. Betting on MCP is betting on the protocol layer. Betting on Mem0 is betting on the product layer. You can and should do both.

## 4. Updated Portfolio Strategy (Two-Track)

### Track 1: MCP Rust SDK contributions (primary)

Remains the top recommendation from [2026-04-14-portfolio-strategy-ai-engineer.md](2026-04-14-portfolio-strategy-ai-engineer.md). The foundation donation + multi-vendor adoption + 97M installs **strengthen** this bet. Contributions to the Rust SDK compound over years.

### Track 2: Mem0 as a second credential (supplemental)

Weave Mem0 into the existing plan cheaply — don't contribute instead of MCP, contribute alongside:

1. **Include Mem0 in the eval harness** (already planned). Head-to-head vs corvia gives real hands-on experience with the market leader.

2. **Build corvia as a Mem0-compatible adapter.** Expose a Mem0-API-compatible surface so corvia becomes a drop-in replacement demo. "Local-first + MCP-native Mem0 alternative" is a concrete story hiring managers at Mem0, Zep, and their customers immediately understand.

3. **One integration-focused blog post.** "Bridging Mem0 and MCP: wrapping Mem0 behind an MCP server." Useful content, ties both worlds, positions as fluent in both layers.

4. **Optional: one Mem0 PR.** Framework adapter, backend connector, or bug fix. Supplemental signal, not primary.

### The layered interview story

> "I built corvia, a local-first Rust MCP memory server. Benchmarked it against Mem0, Zep, and Letta on LongMemEval — here are the numbers. Contributed to the MCP Rust SDK to deepen protocol-level knowledge and fix a production pain point. MCP is the durable protocol layer, Mem0 is the product leader in managed memory — here's where each breaks down in practice."

~40 seconds. Covers memory expertise, protocol fluency, evals, OSS contribution, strategic thinking, opinions backed by numbers.

## 5. The Real Risk: Commoditization, Not Obsolescence

The thing to actually worry about is **MCP commoditization**, not phase-out. In 12-18 months, "I know MCP" will be table stakes like "I know REST" is today. That makes **early contribution now** more valuable, not less.

Being an MCP contributor in April 2026 carries weight that "I've used MCP" won't carry in April 2027. Timing is ideal. Act on it.

## 6. Action Items

1. Do not abandon MCP Rust SDK track. If anything, accelerate.
2. Explicitly include Mem0 in the eval harness run list.
3. Add a corvia ↔ Mem0 compatibility layer as a portfolio demo (scope TBD).
4. Plan one integration blog post in addition to the MCP + memory benchmark posts.
5. Keep Mem0 OSS contribution as optional, not required.

## Sources

- [A Year of MCP — Pento](https://www.pento.ai/blog/a-year-of-mcp-2025-review)
- [Anthropic donates MCP to Linux Foundation](https://www.anthropic.com/news/donating-the-model-context-protocol-and-establishing-of-the-agentic-ai-foundation)
- [MCP 97 Million Installs](https://vucense.com/ai-intelligence/ai-tools/mcp-97-million-installs-ai-agent-standard-2026/)
- [Why the Model Context Protocol Won — The New Stack](https://thenewstack.io/why-the-model-context-protocol-won/)
- [Mem0 $24M Series A — TechCrunch](https://techcrunch.com/2025/10/28/mem0-raises-24m-from-yc-peak-xv-and-basis-set-to-build-the-memory-layer-for-ai-apps/)
- [Mem0 Series A announcement](https://mem0.ai/series-a)
