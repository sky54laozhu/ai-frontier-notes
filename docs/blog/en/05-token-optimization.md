---
title: 'Token Economics — A Cost Optimization Playbook for Full-Lifecycle Claude Code Development'
slug: 05-token-optimization
date: 2026-06-10
series: ai-frontier-notes
series_index: 5
keywords: [Claude Code, Token Optimization, Cost Control, Prompt Caching, Model Selection, Subagent, Full-Lifecycle Development]
prev: 04-loop-driven-development
canonical: https://github.com/sky54laozhu/ai-frontier-notes/blob/main/docs/blog/en/05-token-optimization.md
---

# Token Economics — A Cost Optimization Playbook for Full-Lifecycle Claude Code Development

> The first four posts covered Loop Engineering theory (01), complex Loop implementation (02), Hello World onboarding (03), and full-lifecycle LDD (04). This post tackles an unavoidable reality: **when you run an entire project through Claude Code, how do you manage token spend?** The answer isn't "use AI less" — it's **use the right model at the right phase, and manage context at the right time**.

**Jump to:** [The Problem](#the-problem-2-million-tokens-in-one-build-session) · [Naive Approach](#naive-approach-cut-everywhere) · [Core Solution](#core-solution-segment-by-phase-model-and-context) · [Strategy 1: Model Tiering](#strategy-1-model-tiering--the-right-model-for-the-right-job) · [Strategy 2: Context Hygiene](#strategy-2-context-hygiene--every-message-pays-for-your-history) · [Strategy 3: Subagent Isolation](#strategy-3-subagent-isolation--keep-noise-in-a-side-room) · [Strategy 4: Prompt Cache](#strategy-4-prompt-cache-warmth--the-hidden-90-discount) · [LDD Five Phases](#back-to-ldd-cost-optimization-across-five-phases) · [Counter-Intuitive Conclusions](#counter-intuitive-conclusions)

## The Problem: 2 Million Tokens in One Build Session

The LinkShort project from Post 04 ran five phases of Loops in ~40 minutes. If you run the whole thing on Opus with no optimization in a single mega-session, cumulative input tokens can reach **2 million**. At Opus 4.8 pricing ($5/MTok input, $25/MTok output), a small project easily costs $10-15.

This isn't extreme. Enterprise data shows developers average **$13/active day**, $150-250/month. But 90% of developers stay under **$30/day** — the difference is cost optimization.

**The fundamental cost formula**:

```
Per-turn cost = (system prompt + CLAUDE.md + conversation history + tool defs) × input price
              + (thinking tokens + output text + tool calls) × output price
```

Key insight: **every message re-sends the entire conversation history**. Turn 1 sends 10K tokens, turn 10 sends 100K, turn 50 sends 500K — **cost grows quadratically**, not linearly.

## Naive Approach: "Cut Everywhere"

Most people's first instinct:

1. Talk to AI less (fewer interactions)
2. Always use the cheapest model
3. Write the shortest prompts possible
4. Avoid Subagents (because "they cost more")

**Why this fails**:

- **Less talking = less output.** You're paying for Claude Code to do work. Fewer interactions means less work done.
- **Cheapest model on hard decisions = rework.** Haiku writing a Spec produces a poor Spec. The Build Loop will faithfully implement the wrong requirements (the core insight from Post 04), and the entire pipeline runs for nothing — **rework costs 10x more than the model price difference**.
- **Shorter prompts = wasted exploration.** "Fix auth" makes Claude scan the entire project for auth-related files, consuming far more tokens than the few you saved in the prompt.
- **No Subagents = bloated main context.** Test outputs, logs, and code exploration all pile into the main thread. Every subsequent turn carries that noise — getting more expensive over time.

The naive approach confuses **"spending less" with "spending wisely."** The real goal is doing more with the same money, or doing the same with less.

## Core Solution: Segment by Phase, Model, and Context

Four strategies, ranked by impact:

![Four Token Optimization Strategies Overview](../assets/img/05-four-strategies.svg)

## Strategy 1: Model Tiering — The Right Model for the Right Job

Mid-2026 Anthropic pricing for three model tiers:

| Model | Input ($/MTok) | Output ($/MTok) | Multiplier (vs Haiku) |
|-------|:---:|:---:|:---:|
| **Haiku 4.5** | $1 | $5 | 1x |
| **Sonnet 4.6** | $3 | $15 | 3x |
| **Opus 4.8** | $5 | $25 | 5x |

A 5x price spread means **model selection is the biggest cost lever**.

**Practical rules**:

- **Use Opus for phases that need deep reasoning**: Spec decomposition, Plan architecture, complex root cause analysis. Quality in these phases determines correctness of everything downstream — **saving $1 on Spec can waste $10 in Build**.
- **Use Sonnet for 80% of coding work**: Writing code, running tests, code review. Sonnet 4.6 is close to Opus on code generation, 40% cheaper.
- **Use Haiku for simple judgments**: Acceptance test execution, formatting, renaming, JSON conversion. Haiku is 5x cheaper and more than sufficient.

Switching models in Claude Code:

```bash
/model sonnet
/model opus
/model haiku

# Or use opusplan mode: Opus for planning, auto-switch to Sonnet for generation
```

**Note**: Opus 4.7+ uses a new tokenizer that consumes ~**35% more tokens** for the same text. This makes the actual cost of Opus even higher — reinforcing the "Opus only for critical phases" strategy.

## Strategy 2: Context Hygiene — Every Message Pays for Your History

Context management is the second-biggest lever. Core principle: **every message re-reads your entire conversation history**.

### /clear: Fresh start when switching tasks

```bash
# ❌ Wrong: one session for everything
claude> write spec...(10 turns)
claude> write plan...(10 more)  # each turn carries 20 turns of spec history
claude> write code...(30 more)  # each turn carries 50 turns of history → explosion

# ✅ Right: one session per phase
claude> write spec...
claude> /clear
claude> read docs/spec.md, write plan...
claude> /clear
claude> read docs/plan.md, write code...
```

One team switched from mega-sessions to focused sessions: **average session cost dropped from $2.87 to $0.94**.

### /compact: Proactively compress at 40-50%

Claude Code auto-compacts at 83.5% context usage. But quality has already degraded by then — **proactively `/compact` at 40-50% works better**.

```bash
# Compact with instructions on what to preserve
/compact Keep the task list and completed status, drop debugging traces
```

Measured impact: a 27-turn customer service agent used 150K cumulative input tokens without compaction, 79K with — **47% savings**.

### CLAUDE.md: Keep it under 200 lines

CLAUDE.md is **sent on every single turn**. A 5,000-token CLAUDE.md across 50 turns costs 250K extra tokens.

Put stable instructions there (how to run tests, package manager, formatting rules). Move specialized workflow guides into **Skills** that load on-demand.

### .claudeignore: Exclude noise files

```
node_modules/
dist/
.git/
*.lock
coverage/
```

These files Claude doesn't need to see. Excluding them reduces tokens consumed during file scanning.

## Strategy 3: Subagent Isolation — Keep Noise in a Side Room

Subagents are isolated Claude instances with their own context windows. Intermediate results stay in the sub-context; only the final summary returns to the main thread.

**When to use Subagents**:

| Scenario | Without Subagent | With Subagent | Difference |
|----------|:---:|:---:|:---:|
| Run tests (3000-line output) | 3000 lines into main context | Returns "7/7 passed" | Main context saves ~99% |
| Code exploration (20 files) | 150-300K tokens into main | Returns 500-word summary | Main context saves ~98% |
| Log analysis (10K lines) | All into main context | Returns "3 ERRORs found" | Main context saves ~99% |

**When NOT to use Subagents**:

- **Small tasks** (a single git command, renaming a variable) — startup overhead isn't worth it
- **Coupled tasks** — Subagents can't see each other's context
- **Tight budgets** — multi-agent workflows use 4-7x total tokens. Main context is cleaner, but aggregate usage is higher

**Decision rule**: Use a Subagent when **main context savings > Subagent startup overhead**. Rule of thumb: if the task reads > 3 large files → use a Subagent.

**Cost tip**: Subagents inherit the main thread's model by default. But exploration Subagents can use Haiku (the built-in Explore Agent defaults to Haiku), and review Subagents can use Sonnet.

## Strategy 4: Prompt Cache Warmth — The Hidden 90% Discount

The most overlooked strategy. Claude Code automatically enables Prompt Caching:

| Token Type | Price (Opus) | vs Normal Input |
|------------|:---:|:---:|
| Normal input | $5/MTok | 100% |
| **Cache read** | $0.50/MTok | **10%** |
| Cache write | $6.25/MTok | 125% (one-time) |

**90% discount** — but with one condition: **the cache expires after 5 minutes without a hit**. Each hit resets the 5-minute timer.

**Practical implications**:

```bash
# ✅ Active session → cache stays warm, most input costs 1/10
claude> edit code (minute 1)
claude> run tests (minute 3)   # cache warm, 90% savings
claude> fix bug (minute 5)     # cache warm, 90% savings

# ❌ Go idle for 10 minutes → cache expires, full price rebuild
claude> edit code (10:00)
# ... 10-minute meeting break ...
claude> continue (10:10)  # cache expired, full price this turn
```

**Critical trap**: After idling > 5 minutes, if you run `/compact` — it **reprocesses the entire conversation at full price** to generate the summary. **Correct approach: use `/clear` to start fresh after idle, not `/compact`**.

## Strategy 5: Thinking Token Cap — The Single Biggest Lever

Extended Thinking is Claude's "reasoning process," billed at **output token prices**. Opus output costs $25/MTok, and the default thinking budget can reach tens of thousands of tokens.

```bash
# Cap thinking tokens at 10K (default can be 50-100K)
export MAX_THINKING_TOKENS=10000
```

**Why 10K is enough**: Beyond 10K tokens of thinking, marginal returns on most coding tasks are negligible. Measured impact: **30-40% savings from this single change** — because it cuts the most expensive output tokens.

**Adjust by phase**:

- Spec/Plan: Keep default (deep reasoning needed)
- Build: `MAX_THINKING_TOKENS=10000` (coding doesn't need long reasoning chains)
- Accept: `MAX_THINKING_TOKENS=5000` (verification is simpler)

## Back to LDD: Cost Optimization Across Five Phases

Mapping all five strategies onto the LDD pipeline from Post 04:

![LDD Five Phases Cost Optimization Mapping](../assets/img/05-phase-cost-mapping.svg)

| Phase | Model | Session | Subagent | Thinking | Est. Cost |
|-------|-------|---------|----------|----------|-----------|
| **Spec** | Opus | Isolated | Not needed | Default | ~$0.50 |
| **Plan** | Opus | Isolated | Not needed | Default | ~$0.40 |
| **Build** | Sonnet | Per-task isolated | Test output via Subagent | 10K cap | ~$3.20 |
| **Review** | Sonnet | Isolated | Diff analysis via Subagent | 10K cap | ~$0.60 |
| **Accept** | Haiku | Isolated | Not needed | 5K cap | ~$0.15 |
| **Total** | — | — | — | — | **~$4.85** |

Compared to all-Opus + mega-session at ~$11.70: **59% savings**.

**Copy-paste command sequence**:

```bash
# Phase 1: Spec (Opus, deep reasoning)
/model opus
claude -p "Read CLAUDE.md. Generate docs/spec.md from this requirement..."
/clear

# Phase 2: Plan (Opus, deep reasoning)
/model opus
claude -p "Read docs/spec.md, generate docs/plan.md..."
/clear

# Phase 3: Build (Sonnet, capped thinking)
export MAX_THINKING_TOKENS=10000
/model sonnet
claude -p "Read docs/plan.md, implement Task 1..."
/clear
claude -p "Read docs/plan.md, implement Task 2..."
/clear
# ... one session per task ...

# Phase 4: Review (Sonnet)
/model sonnet
claude -p "Independent code review, git diff main...HEAD..."
/clear

# Phase 5: Accept (Haiku)
/model haiku
claude -p "Start service, verify acceptance criteria from spec..."
```

## Quick Reference: 7 Rules

| # | Rule | Savings | When |
|---|------|:---:|------|
| 1 | Cap Thinking Tokens at 10K | 30-40% | Build/Review/Accept phases |
| 2 | Opus for Spec/Plan, Sonnet for Build, Haiku for Accept | 40-80% | Always |
| 3 | /clear between each Phase | 60-70% | When switching phases |
| 4 | /compact proactively at 40-50% context | ~47% | During long sessions |
| 5 | CLAUDE.md under 200 lines | Continuous | At project setup |
| 6 | Subagent for heavy I/O | Variable | Tests, logs, code exploration |
| 7 | /clear (not /compact) after > 5 min idle | Avoids waste | When returning to work |

![Seven Rules Priority and Use Cases](../assets/img/05-seven-rules.svg)

## Counter-Intuitive Conclusions

> **The most expensive tokens aren't Opus tokens — they're rework tokens.**

Most people assume "Opus is too expensive." But spending an extra $0.30 on Opus for the Spec phase buys a more precise requirements document — preventing the Build Loop from going sideways on a vague Spec. **One round of rework ($3-8) far exceeds the Opus-vs-Sonnet price difference ($0.30).** The key to saving money isn't "use the cheapest model" — it's "use the expensive model where it prevents downstream rework."

More counter-intuitive: **Subagents look more expensive (4-7x total tokens) but are actually cheaper.** A 50-turn mega-session without Subagents means the last 30 turns each carry 20 turns of test outputs and exploration results — those tokens burn money every turn. "Total tokens higher" is a misleading metric. What matters is **per-turn cost of the main context**, not aggregate token count. After isolating noise into Subagents, the main context stays lean and every subsequent turn is cheaper.

Most counter-intuitive: **The biggest cost lever isn't any technical strategy — it's "pause 5 seconds and think before you prompt."** A precise prompt ("optimize the login function in src/auth.ts — extract constants, add error handling") versus a vague prompt ("fix auth") can differ by 10x in token consumption — the latter triggers a full-project scan, multiple clarification rounds, and trial-and-error execution. **Your 5 seconds of prompt crafting is worth $1-5 in token savings.** This echoes Post 04's conclusion: your role is decision-maker, not executor — and decision quality directly determines execution cost.

---

## Diagrams

1. ![Four Strategies Overview](../assets/img/05-four-strategies.svg)
2. ![LDD Five Phases Cost Mapping](../assets/img/05-phase-cost-mapping.svg)
3. ![Seven Rules Priority](../assets/img/05-seven-rules.svg)

---

📌 Series reading map: [reading-map.md](../reading-map.md)
🔗 Previous: [04 Loop-Driven Development](../zh/04-loop-driven-development.md)
