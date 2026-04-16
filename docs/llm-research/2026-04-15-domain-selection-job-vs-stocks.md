# Domain Selection: Malaysia AI Agent Landscape + Job-Hunting vs Stocks Analysis

Date: 2026-04-15
Context: Technology direction is set (custom harness in Python, Gemini Flash for dev, provider-agnostic, corvia as memory). Now picking the domain for the first shipped agent. Personal use cases in scope: job hunting and stocks analysis. This doc deep-dives the Malaysia AI agent market to inform the choice.

Companion docs:
- [2026-04-14-portfolio-strategy-ai-engineer.md](2026-04-14-portfolio-strategy-ai-engineer.md)
- [2026-04-15-malaysia-agent-builder-reeval.md](2026-04-15-malaysia-agent-builder-reeval.md)

## 1. Malaysia AI Agent Domain Landscape

Based on JD scraping (Jobstreet, LinkedIn MY, Hiredly, MyCareersFuture cross-listings), public announcements from local AI teams, and observable product launches. This is not a vendor report — it is a working map for a job-hunting engineer.

### 1.1 Domains with real AI engineering hiring in MY

| Domain | Hiring intensity | Common agent use cases | Differentiation potential |
|---|---|---|---|
| **Fintech / banking** | Very high | Fraud detection, KYC/AML automation, customer ops, risk scoring, advisory chatbots | High — Bursa, Islamic finance, local regulation |
| **Islamic finance / Shariah** | Medium-high, growing | Shariah screening, halal certification, zakat calculation, sukuk analysis | Very high — globally underserved, MY is a center |
| **Insurance / takaful** | High | Claims triage, underwriting assistance, document extraction, policy Q&A | Medium — takaful angle is differentiated |
| **E-commerce** (Shopee, Lazada, local SME) | High | Search relevance, product Q&A, customer service, listing generation | Low — Shopee/Lazada do this in-house with tier-1 teams |
| **Property tech** | Medium | Listing analysis, rent-vs-buy, landlord assistants, valuation | Medium — iProperty/PropertyGuru ecosystem, Malay content |
| **Telco** (Maxis, Celcom/Digi, U Mobile) | Medium | Churn prediction, customer service, plan recommendation | Low — commodity work |
| **Manufacturing / semi** (Penang) | Medium | Document automation, quality inspection, supply chain | Low for LLM agents specifically |
| **Oil & gas** (Petronas + contractors) | Medium | Technical document Q&A, safety compliance, reservoir notes | Low — hard to demo without insider data |
| **Government / MyDigital** | Low but strategic | Citizen services, LHDN/tax, MyGov navigation | Medium — nobody has shipped a good one |
| **Legal / compliance SME** | Low | Contract review, SSM filings, employment law Q&A | Medium — MY legal corpus is underserved |
| **HR / recruiting** | Medium | Resume screening, candidate ranking, interview scheduling | Medium — mirror of job hunting |

### 1.2 What local interviewers resonate with

Soft-signal ranking from JDs and conversation patterns, not hard data:

1. **Fintech / banking** — Maybank, CIMB, Public Bank, RHB, Alliance, Ambank all have AI teams. GXBank and AEON Bank (digital banks) are newer and hungrier. Every one of them has a "customer agent" or "advisory agent" roadmap item. Showing a financial agent immediately maps to their current backlog.
2. **Islamic finance** — under-discussed but strong. Malaysia positions itself as the global hub for Islamic finance. Shariah compliance is a genuine unsolved AI problem: it requires knowledge of AAOIFI/MASB standards, screening methodology, and ongoing monitoring. A tool here has almost zero US competition.
3. **E-commerce / marketplace ops** — respected but saturated inside Shopee/Lazada. Demoing to them is hard; demoing to SME sellers using their platforms is easier and differentiated.
4. **Insurance / takaful** — claims automation is a wide-open problem locally. Prudential, AIA, Etiqa, Great Eastern all have initiatives.
5. **Government / public services** — high mission resonance, low commercial hiring volume. Good for a side demo, bad as primary portfolio.

### 1.3 Domains to avoid as portfolio centerpieces

- **Generic customer service chatbot** — crowded, commoditized, every vendor sells one. Nothing to prove.
- **"AI for SME in X industry"** without a specific industry — too vague, no interviewer can place it.
- **Pure tutorial reproductions** (PDF Q&A, "chat with your docs") — tutorial smell is strong and signal is weak.
- **Anything that requires Bahasa Malaysia as a hard dependency** on day one. BM LLM quality is uneven; save BM as a stretch feature, not a blocker.

## 2. The Two Candidates

Both are real personal use cases for the owner. The question is which makes the better first shipped agent.

### 2.1 Job-hunting agent

**What it would do:** take a JD URL, extract requirements, score against the candidate's resume/profile, draft a cover letter, track the application, remember rejection reasons, suggest skill gaps to close.

**Tools the harness would call:** JD fetcher (HTTP), HTML cleaner, resume parser, LLM scorer, cover letter drafter, application tracker (corvia write), follow-up scheduler.

**Memory shape:** application history, company research snapshots, recurring rejection themes, interviewer names, stages reached, offer comparisons. This is a good fit for corvia.

**Why it is tempting:**
- The owner is currently job-hunting. Dogfood is automatic.
- Immediate personal ROI — the agent earns its build cost directly.
- Feedback loop is continuous (every application is a test case).

**Why it is weak as a portfolio centerpiece:**
- **Saturated.** Every AI bootcamp grad ships one. It has become the "todo app" of agents.
- **Universal, not Malaysia-specific.** No local moat, no interviewer head-nod that says "you understand my market."
- **Small-N eval.** Ground truth is delayed weeks (callbacks, offers) and confounded by everything. Hard to generate a numbers-backed blog post in 3 weeks.
- **Legal/TOS fragility.** Scraping LinkedIn/Jobstreet invites account bans. MyCareersFuture is Singapore. Hiredly has an API but limited coverage.
- **Awkward interview dynamic.** Showing a hiring manager "the tool I built to apply to your job" is not a clean pitch.

### 2.2 Stocks analysis agent

**What it would do:** accept a Bursa Malaysia ticker, fetch financials and filings, compute ratios against peers, pull recent news and analyst coverage, check Shariah compliance status, write a structured research note (bull/bear/neutral thesis with evidence), remember the thesis over time, and update it when new data arrives.

**Tools the harness would call:** yfinance (or i3investor/KLSE Screener scraper) for price + ratios, Bursa announcement fetcher, The Edge / The Star news fetcher, Shariah-compliant list lookup (SC Malaysia maintains this publicly), peer finder, annual report PDF parser, note writer, thesis tracker (corvia write/read).

**Memory shape:** company profile, historical thesis evolution, prior mistakes and corrections, news timeline, peer set, Shariah status changes over time, ratio history. This is an exceptionally good fit for corvia — memory is not a bolt-on, it is the product.

**Why it is strong:**
- **Malaysia-specific differentiator.** Bursa + Shariah compliance is a niche that US-trained tools handle poorly or not at all. Genuine moat in interviews with any fintech team.
- **Concrete numeric eval.** Backtest thesis signals against historical returns. Compare note quality against The Edge coverage. LLM-as-judge against human analyst notes. Multiple clean paths to numbers for a blog post.
- **High fintech interview resonance.** Maybank Invest, CIMB Securities, Kenanga, RHB Research, Rakuten Trade, Moomoo MY, StashAway, Wahed Invest — all of these are targets and all of them immediately understand the demo.
- **Memory is the product, not the decoration.** Longitudinal thesis tracking is something no other agent does well, and it is exactly what corvia is shaped to support. The demo writes itself: "here is the same ticker analyzed six months apart, here is how the thesis evolved, here is where the agent admitted it was wrong."
- **Public data, low legal risk.** Bursa filings, yfinance, SC Shariah list, news sites with reasonable use patterns. No LinkedIn TOS roulette.
- **Clean scope boundary.** "Research assistant, not advisor" framing handles regulatory concerns. Put a disclaimer at the top of every note and move on.

**Why it is harder than it looks:**
- **Data plumbing.** Bursa data is less polished than US equities. yfinance coverage of Bursa tickers is patchy; some fields missing. Expect to build a thin aggregation layer.
- **PDF parsing of annual reports.** Real work. Plan for it or scope it out of v1.
- **"Not financial advice" framing must be lived, not just disclaimed.** The agent should produce research notes, not buy/sell calls.
- **Crowded with hobbyist quant blogs.** The differentiation is not "LLM picks stocks" — it is "LLM writes longitudinal research with memory, specialized on Bursa + Shariah." Framing is load-bearing.

## 3. Scoring Matrix

Same axes as the Malaysia rubric in the reeval doc, plus domain-specific ones. Scores are 1-10, honest not generous.

| Criterion | Job hunting | Stocks analysis | Notes |
|---|---|---|---|
| Malaysia interview resonance | 4 | 9 | Fintech hiring intensity is very high, Bursa specialization is rare |
| Personal dogfood value today | 10 | 7 | Owner is literally job hunting now |
| Shippability in 2-3 weeks | 6 | 7 | Data plumbing roughly equal, job-hunt scraping is flakier |
| Data availability / legal risk | 5 | 8 | Public filings beat LinkedIn TOS |
| Eval clarity (numbers for blog) | 4 | 9 | Backtest > "did I get a callback" |
| Compounds with corvia's memory story | 8 | 9 | Longitudinal thesis tracking is corvia's best demo surface |
| Portfolio differentiation | 3 | 8 | Saturated vs niche |
| Writes the loop clearly (harness demo) | 7 | 8 | Both have real multi-step tool chains |
| Blog-post potential | 5 | 9 | "I benchmarked an LLM stock researcher against The Edge" is a strong post |
| Risk of looking bad | 5 | 6 | Bad JD match is embarrassing, bad stock call is embarrassing too — both manageable with framing |
| **Total** | **57** | **80** | |

The margin is wide enough to be decisive.

## 4. Recommendation

**Build the stocks analysis agent first.** Specifically, as a longitudinal research assistant for Bursa Malaysia tickers, with Shariah compliance awareness as a differentiated feature. Not a stock picker, not a tipping service — a research note generator with memory.

Working name: something honest like `kajibursa` (kaji = research, BM) or `bursa-research-agent`. Naming matters less than the framing: **research assistant, not advisor**.

### 4.1 Shape of v0.1 (2-3 weeks on the harness)

**In scope:**
- Ticker input (e.g., `5347.KL` for Tenaga)
- Fetch price, basic ratios, 1Y history (yfinance or i3investor)
- Fetch latest 5 Bursa announcements (public RSS or scrape)
- Fetch Shariah compliance status from SC Malaysia list
- Produce a structured research note: company overview, recent ratios vs industry, news summary, bull case, bear case, open questions
- Write the note to corvia with ticker + date
- Re-run later: read prior note, diff new data, produce an update note highlighting changes in thesis

**Explicit v0.1 non-goals:**
- No buy/sell recommendations
- No portfolio construction
- No backtesting engine yet
- No annual report PDF parsing yet
- No Bahasa Malaysia output yet
- No web UI — CLI and markdown output is fine
- No multi-ticker batching

**Stretch (v0.2+):**
- Peer comparison (same Bursa sector)
- Historical thesis evolution view (the killer demo)
- Backtest: did the bull/bear tilt correlate with 6-month returns
- Annual report PDF parsing (big work, do it only after v0.1 ships)
- Side-by-side with The Edge / RHB / Kenanga research notes as the eval set

### 4.2 Evaluation plan for the blog post

One or more of:

1. **Agreement with human analysts.** Sample 20 Bursa tickers. Run the agent. LLM-as-judge compares the agent's thesis against The Edge and broker research published within a 2-week window. Report agreement rate on direction (bull/bear/neutral) and ratio/fact accuracy.
2. **Signal backtest.** For the same 20 tickers, check whether the agent's bull/bear tilt correlated with 3-month forward returns. Small N, clear caveat, honest numbers. Not a performance claim — a calibration check.
3. **Longitudinal consistency.** Re-run the agent a month later. Does the updated thesis cohere with the original? Does it flag its own mistakes? This is the memory demo.
4. **Latency and cost per note.** Token spend, tool-call count, wall-clock time. Useful numbers, easy to measure.

Any one of these gives the blog post numbers. Two of them makes it bulletproof.

## 5. What Happens to the Job-Hunting Use Case

The owner is actually job hunting right now, so dropping the use case entirely is dumb. But it does not need to be the portfolio centerpiece.

**Keep job hunting as a Claude Code superpowers skill + MCP tools inside corvia.** This is exactly Option B from the original portfolio strategy doc: zero new harness work, zero marginal API cost (runs on Max), immediate personal value.

The split:

| Track | Purpose | Effort | Cost |
|---|---|---|---|
| **Stocks agent on custom harness** | Portfolio centerpiece, blog, interview demo | 2-3 weeks | Gemini free tier + ~$20 Claude for the demo |
| **Job-hunt skill inside Claude Code** | Personal dogfood during the active hunt | Half a week | $0 (runs on Max) |

The job-hunt skill does not need to be public. It does not need a blog post. It earns its keep by helping the owner land the job that the stocks agent's blog post helps them get interviews for.

**Bonus alignment:** fintech interviews from the stocks agent's blog post are exactly the ones where the job-hunt skill is useful.

## 6. Risks and Counterarguments

**"What if the stocks agent produces bad calls and I look foolish?"** Framing prevents this. Research notes with explicit bull and bear cases cannot be "wrong" the way a buy recommendation can. Always include "what I do not know" as a section. Every note carries a disclaimer. The demo narrative is "look at the research quality and the longitudinal memory," not "look at the returns."

**"I am not a finance expert."** You do not need to be. The agent is reading public information, computing standard ratios, and summarizing. The differentiation is longitudinal memory and Bursa coverage, not alpha generation. If interviewers want quant alpha, they are hiring a different role.

**"Job hunting is more urgent."** True, and the cheap Claude-Code-skill version handles it directly. The stocks agent is the portfolio artifact that gets the interviews; the job-hunt skill is the tool that handles the applications. Different jobs.

**"Shariah compliance is niche and I do not know the rules."** SC Malaysia publishes the current Shariah-compliant list directly. The agent does not rule on compliance — it fetches the status from the authoritative source and annotates. That is a data-lookup feature, not a fiqh engine.

**"Bursa data is messy."** True. Budget the first 2-3 days of the build on a data-plumbing spike before committing. If yfinance coverage is unacceptable, fall back to i3investor or KLSE Screener scraping. If all three fail, the doc gets rewritten. Unlikely given public data sources exist.

**"Could I do both at once?"** Not as portfolio centerpieces. Doing both at full depth in 3 weeks leads to neither shipping. The split above is the actual way to get both: one serious, one cheap.

## 7. Action Items

1. **This week:** data-plumbing spike. Pick 3 Bursa tickers (Tenaga, Maybank, Petronas Chemicals). Confirm yfinance coverage is adequate for basic ratios and history. If not, test i3investor/KLSE Screener. 2 days max.
2. **Week 1 (parallel):** create the harness repo from the prior doc and get v0.1 loop running with a single `http_get` tool. Gemini Flash provider.
3. **Week 2:** add tools: `bursa_snapshot`, `bursa_announcements`, `shariah_status`, `research_note_write`. Wire corvia as memory backend over MCP.
4. **Week 2-3:** first end-to-end research note on one ticker. Iterate on note structure. Add "re-run with prior note in memory" flow — the longitudinal demo.
5. **Week 3:** run on 10-20 tickers. Capture one eval number (agreement with analyst sentiment, or cost/note, or both).
6. **Week 3-4:** blog post draft: "I built a Bursa research agent with longitudinal memory. Here is what it gets right and wrong."
7. **Parallel, cheap:** a `/job-hunt` superpowers skill for Claude Code, 2-3 days of work, used during the actual hunt.

## 8. Key Strategic Insights

1. **The Malaysia domain map favors fintech for AI engineering hires.** Bursa + Shariah is the least-crowded differentiated corner of that map.
2. **Stocks analysis framed as research, not advice, neutralizes the biggest risk** (bad calls) while preserving the biggest upside (numbers-backed demo).
3. **Longitudinal memory is the killer feature** and it happens to be what corvia does best. The agent and the memory product mutually validate each other.
4. **The job-hunting use case is not abandoned — it is routed to the cheap track** (Claude Code skill) while the expensive track (custom harness + shipped agent) goes where the portfolio upside is.
5. **One serious agent beats two half-agents.** The doc's strongest recommendation is to resist the temptation to do both at full depth.

## Sources

Internal synthesis from prior research docs and domain knowledge. External validation still pending:
- SC Malaysia Shariah list source (to confirm format and update cadence)
- Bursa announcement RSS / scraping feasibility
- yfinance `.KL` ticker coverage quality
- The Edge Markets access patterns (free vs paywalled)

A follow-up doc after the data-plumbing spike is expected.
