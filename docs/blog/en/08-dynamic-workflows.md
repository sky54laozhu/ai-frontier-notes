---
title: 'Dynamic Workflows in Practice — From Hand-Written Orchestration to Claude Writing Its Own'
slug: 08-dynamic-workflows
date: 2026-06-11
series: ai-frontier-notes
series_index: 8
keywords: [Dynamic Workflows, Claude Code, ultracode, multi-agent, Loop Engineering, orchestration, adversarial verification, workflow]
prev: 07-model-orchestration
canonical: https://github.com/sky54laozhu/ai-frontier-notes/blob/main/docs/blog/en/08-dynamic-workflows.md
---

# Dynamic Workflows in Practice — From Hand-Written Orchestration to Claude Writing Its Own

> The first seven posts covered Loop Engineering theory (01), practice (02), Hello World (03), full-lifecycle LDD (04), Token economics (05), stuck troubleshooting (06), and model orchestration (07). Post 07 used Shell scripts to automate "switch models per phase" — but the orchestration logic was still yours to write. This post answers the cliffhanger from 07: **can we make Claude write the orchestration itself?** The answer is Dynamic Workflows — Claude generates JS orchestration scripts on demand, coordinating tens to hundreds of subagents in parallel. We walk through it step by step with the LinkShort project.

**Jump to:** [Problem](#problem-three-ceilings-of-shell-orchestration) · [Core Concept](#core-concept-what-are-dynamic-workflows) · [Three Activation Methods](#three-activation-methods) · [Six Patterns](#six-orchestration-patterns) · [Hands-on 1: Rewrite LDD Pipeline](#hands-on-1-rewrite-the-ldd-pipeline-with-a-workflow) · [Hands-on 2: Deep Code Review](#hands-on-2-deep-code-review-with-a-workflow) · [Hands-on 3: Codebase Exploration](#hands-on-3-codebase-exploration-with-a-workflow) · [Performance & Cost](#performance-and-cost) · [When Not to Use](#when-not-to-use-workflows) · [Counter-Intuitive Conclusions](#counter-intuitive-conclusions)

## Problem: Three Ceilings of Shell Orchestration

Post 07's `ldd-loop.sh` solved "auto-switch models per phase + closed-loop retry." But in practice, it hits three ceilings:

**Ceiling 1: Hard-coded orchestration logic.** The script defines five phases, two loop layers, and an escape valve — changing a phase means changing Bash. Want to add a "security scan" between Build and Review? Edit Bash. Want to replace single-agent Review with three independent reviewers? Edit Bash. Every requirement change demands manual script edits.

**Ceiling 2: Mostly serial.** `ldd-loop.sh`'s Build phase is one `claude -p` call — the agent processes 8 tasks sequentially inside. Task 3 (POST /api/shorten) and Task 5 (GET /api/stats) have no dependency — they could run in parallel. But implementing "dependency-aware parallelism" in Shell would triple the code.

**Ceiling 3: No adversarial verification between agents.** Post 07's Review is one agent checking all code. But a single agent reviewing its own project's code exhibits **self-preferential bias** — it tends to find the code correct. You need multiple independent agents reviewing from different angles, challenging each other's conclusions. This is nearly impossible in Shell.

**All three ceilings share one root cause: the orchestration logic is in human hands.** Dynamic Workflows solve this by handing orchestration to Claude.

## Core Concept: What Are Dynamic Workflows

Dynamic Workflows shipped in Claude Code on May 28, 2026 (v2.1.154+, Research Preview).

**One-sentence definition: Claude generates a JS orchestration script on demand, the runtime executes it in the background coordinating dozens to hundreds of subagents, each with its own context window, with intermediate results stored in script variables rather than Claude's context window.**

![Dynamic Workflows Architecture](../assets/img/08-architecture.svg)

### Key Differences from Shell Orchestration

| Dimension | Shell Orchestration (Post 07) | Dynamic Workflows |
|-----------|-------------------------------|-------------------|
| Orchestration logic | Human writes Bash | Claude generates JS |
| Parallelism | Mostly serial, parallelism requires extensive code | Native `parallel()` / `pipeline()` |
| Agent isolation | Each `claude -p` is independent session | Each agent has independent context window |
| Adversarial verification | Manual implementation required | Built-in pattern, Claude auto-generates |
| Intermediate results | Passed via files | Stored in JS variables |
| Repeatability | Script file can be rerun | Save as command, invoke via `/ldd-build` |
| Recoverability | Failure restarts from scratch | Resumable within session, completed agents cached |

### Three Failure Modes Solved

Why can't a single agent do everything in one context window? Because as conversation grows, agents develop three degradation modes:

1. **Agentic Laziness**: Stops before finishing complex multi-step tasks. E.g., reviews 35 of 50 files then says "remaining files have no obvious issues."
2. **Self-Preferential Bias**: Tends to consider its own output correct. Same agent writing then reviewing code rarely finds its own bugs.
3. **Goal Drift**: Loses fidelity to original objectives across compactions. Constraints like "don't use Math.random()" can vanish after the 5th compaction.

Dynamic Workflows solve this: **each subagent has independent context, independent goal, independent termination criteria.** The coding agent doesn't know the review agent exists, and vice versa — structurally eliminating bias.

## Three Activation Methods

### Method 1: Natural Language Request

Say "use a workflow" or "run a workflow" in your prompt:

```
Review all API endpoints under src/routes/ for missing auth checks, use a workflow.
```

### Method 2: The ultracode Keyword

Prefix your prompt with `ultracode`:

```
ultracode: audit all API endpoints under src/routes/ for missing auth checks
```

Claude Code highlights the keyword and triggers workflow mode. Press `Option+W` (macOS) or `Alt+W` (Windows/Linux) to dismiss if unintended.

### Method 3: /effort ultracode (Session-Level)

```
/effort ultracode
```

With this on, Claude auto-generates a workflow for **every substantive task** in the session. Return to normal with `/effort high`.

| What you want | Use which |
|---------------|-----------|
| One-off workflow | Method 1 or 2 |
| Entire session with workflows | Method 3 |
| Try it out | Method 2 (most explicit) |
| Daily dev + occasional workflow | Method 1 (on-demand) |

## Six Orchestration Patterns

Claude selects from and combines six standard patterns when generating workflow scripts. Understanding them helps you guide Claude through your prompts.

![Six Orchestration Patterns](../assets/img/08-six-patterns.svg)

### 1. Classify-and-act

A classifier agent determines task type, then routes to different processing agents.

**Use case**: Support ticket triage — classify (bug / feature / question), then route to fix agent, requirements agent, or Q&A agent.

### 2. Fan-out-and-synthesize

Split task into subtasks, run agents in parallel, wait at a **barrier** for all to complete, then synthesize.

**Use case**: Codebase exploration — one agent per subsystem, synthesize into architecture map.

### 3. Adversarial Verification

For each finding, spawn independent agents that attempt to **refute** it. Only findings that survive refutation are kept.

**Use case**: Security audit — after finding a potential vulnerability, another agent tries to prove "this isn't a real vulnerability." Only confirmed findings are reported.

**This is the most valuable Dynamic Workflows pattern.** Single-agent reviews have high false-positive rates. Adversarial verification structurally eliminates this bias.

### 4. Generate-and-filter

Generate many candidates, score by quality criteria, deduplicate, keep the best.

**Use case**: API naming — generate 20 candidates, score on readability/consistency/brevity, keep top 3.

### 5. Tournament

N agents each attempt the same task, then pairwise comparison selects the winner.

**Use case**: Architecture selection — 3 agents implement with different approaches, judge agents compare pairwise to select the best.

### 6. Loop-until-done

Keep spawning agents until a stop condition is met (no new findings, all errors fixed, budget exhausted).

**Use case**: Bug hunting — scan the codebase repeatedly, stop after 2 consecutive rounds with no new findings.

### Pattern Combinations

| Task | Common Combination |
|------|-------------------|
| Code migration | Fan-out (one agent per file) + Adversarial Verify (review before merge) |
| Deep research | Fan-out (multi-angle search) + Generate-and-filter (dedup) + Adversarial Verify |
| Code review | Fan-out (multi-dimension) + Adversarial Verify (confirm findings) |
| Architecture selection | Generate (multiple approaches) + Tournament (pairwise compare) |
| LDD full lifecycle | Pipeline (phase chaining) + Fan-out (parallel Build) + Adversarial Verify (multi-angle Review) |

## Hands-on 1: Rewrite the LDD Pipeline with a Workflow

**Continuing with the LinkShort project from Post 04.** Same five phases from Spec to Accept, but this time no Shell script — let Claude generate the orchestration.

### Step 1: Launch Your First Workflow

```
ultracode: Build a URL shortener service (LinkShort) using the LDD method.

Requirements: Convert long URLs to short links, click to redirect, view click stats.
Tech stack: Node.js + Hono + SQLite + Drizzle ORM + Vitest + Docker.

Execute in five serial phases:
1. Spec: Generate docs/spec.md (API endpoints, data models, acceptance criteria)
2. Plan: Generate docs/plan.md (task breakdown, dependencies, implementation order)
3. Build: Implement tasks per plan, run tests after each task
4. Review: Review code for security and spec compliance
5. Accept: Verify each acceptance criterion from spec

Use opus for Spec and Plan, sonnet for Build and Review, haiku for Accept.
```

Claude generates a JS orchestration script. Before pressing `Yes`, you can press `Ctrl+G` to inspect it:

```javascript
export const meta = {
  name: 'ldd-linkshort',
  description: 'LDD five-phase pipeline for LinkShort URL shortener',
  phases: [
    { title: 'Spec', detail: 'Generate structured requirements' },
    { title: 'Plan', detail: 'Create implementation plan and task list' },
    { title: 'Build', detail: 'Implement all tasks with tests' },
    { title: 'Review', detail: 'Code review for security and correctness' },
    { title: 'Accept', detail: 'Verify acceptance criteria from spec' },
  ],
}

phase('Spec')
const spec = await agent(
  `You are a product architect. Generate docs/spec.md for a URL shortener service.
   List API endpoints, data models, edge cases, and acceptance criteria.`,
  { model: 'opus', label: 'spec-writer' }
)

phase('Plan')
const plan = await agent(
  `You are a tech lead. Read docs/spec.md, generate docs/plan.md.
   Break into tasks (30-min granularity), with dependencies and implementation order.`,
  { model: 'opus', label: 'plan-writer' }
)

phase('Build')
const build = await agent(
  `You are a senior developer. Read docs/plan.md, implement all tasks in order.
   Run tests after each task. Run the full test suite when done.`,
  { model: 'sonnet', label: 'builder' }
)

phase('Review')
const review = await agent(
  `You are a code review expert. Run git diff to see all changes.
   Check: correctness, security vulnerabilities, performance, spec compliance.
   Fix any critical issues. Output review report to docs/review.md.`,
  { model: 'sonnet', label: 'reviewer' }
)

phase('Accept')
const accept = await agent(
  `You are a QA engineer. Read acceptance criteria from docs/spec.md.
   Start the service, verify each criterion. Output docs/acceptance.md.`,
  { model: 'haiku', label: 'acceptor' }
)
```

**The core difference: you no longer write orchestration code.** You describe "what to do," Claude decides "how to orchestrate."

**Output structure** (same as Post 04 — every phase produces a file):

```
linkshort/
├── CLAUDE.md                    # You write this (tech stack + conventions)
├── docs/
│   ├── spec.md                  # Phase 1 Spec agent output
│   ├── plan.md                  # Phase 2 Plan agent output
│   ├── review.md                # Phase 4 Review agent output
│   └── acceptance.md            # Phase 5 Accept agent output
├── src/                         # Phase 3 Build agent output
│   ├── index.ts
│   ├── routes/
│   └── db/
├── tests/                       # Phase 3 Build agent output
└── Dockerfile                   # Phase 3 Build agent output
```

**The difference from Post 04 isn't the output — it's the process: Post 04 you manually run 5 `claude -p` calls, Post 07 your Bash script runs 5 `claude -p` calls, Post 08 Claude generates the script that runs 5 agents.**

### Step 2: Approval and Monitoring

After Claude generates the script, an approval dialog appears:

| Option | Description |
|--------|-------------|
| **Yes, run it** | Start execution |
| **Yes, and don't ask again** | Start and skip this prompt for this workflow in this project |
| **View raw script** | Inspect the JS source |
| **No** | Cancel |

After `Yes`, the workflow runs in the background. Your session **stays responsive**.

Use `/workflows` to monitor progress:

| Key | Action |
|-----|--------|
| `↑` / `↓` | Select Phase or Agent |
| `Enter` / `→` | Drill into details (prompt, tool calls, result) |
| `Esc` | Back up one level |
| `j` / `k` | Scroll within Agent detail |
| `p` | Pause / Resume |
| `x` | Stop selected agent or entire workflow |
| `r` | Restart selected agent |
| `s` | Save script as command |

### Step 3: Add Adversarial Verification — Multi-Agent Review

The real power of Dynamic Workflows: describe more complex orchestration in natural language.

```
ultracode: Build LinkShort using LDD method.

(Spec, Plan, Build same as above...)

Review phase with adversarial verification:
- Launch 3 independent Review agents, each in isolated context:
  - Agent 1: Security — injection, XSS, auth bypass, path traversal
  - Agent 2: Performance — N+1 queries, memory leaks, concurrency
  - Agent 3: Spec compliance — verify each spec requirement against implementation
- Each agent outputs findings independently
- For each finding, spawn 3 verification agents that try to refute it
- Keep findings confirmed by 2/3 verification agents
- Fix all confirmed issues before proceeding to Accept
```

Claude generates a script using `parallel()` for fan-out review and `pipeline()` for adversarial verification of each finding.

**Comparison with Shell to achieve the same:**

| Feature | Shell Script | Dynamic Workflow |
|---------|-------------|-----------------|
| 3 parallel Review agents | ~40 lines Bash (background processes + wait + merge) | `parallel([...])` one call |
| Adversarial verify (3-vote) | ~60 lines Bash (loop + temp files + vote counting) | `pipeline()` + `parallel()` nested |
| Aggregate + dedup + fix | ~30 lines Bash | A few lines inline JS |
| **Total** | **~130 lines Bash** | **~40 lines JS (auto-generated by Claude)** |

And you don't write those 40 lines of JS — you describe "three-angle adversarial verification" in natural language.

**Adversarial verification output example** (`docs/review.md`):

```markdown
## Three-Angle Review Report

### Security (Agent 1)
- [S-01] src/routes/shorten.ts:12 — No URL protocol validation, allows javascript:
  → Adversarial: 2/3 confirmed ✅ (one verifier said frontend filters, but server shouldn't rely on frontend)
- [S-02] src/routes/redirect.ts:8 — Open redirect, exploitable for phishing
  → Adversarial: 3/3 confirmed ✅
- [S-03] src/db/schema.ts:15 — Short code uses Math.random(), predictable
  → Adversarial: 1/3 confirmed ❌ FILTERED (two verifiers: short codes are public, predictability is not a security risk)

### Performance (Agent 2)
- [P-01] src/routes/redirect.ts:15 — Click recording is synchronous, blocks redirect
  → Adversarial: 3/3 confirmed ✅
- [P-02] src/routes/stats.ts:8 — COUNT(*) on every request, no cache
  → Adversarial: 2/3 confirmed ✅

### Spec Compliance (Agent 3)
- [C-01] Spec requires "same URL returns same short code", implementation generates new code every time
  → Adversarial: 3/3 confirmed ✅

### Summary: 6 findings → 5 confirmed + 1 filtered (S-03 was a false positive)
```

**Note S-03 was filtered.** A single agent would report it as "security issue," but two independent verifiers pointed out that short codes are public information — this is the value of adversarial verification: **not more eyes, but agents challenging each other's premises.**

### Step 4: Add Parallel Build — pipeline vs parallel

LinkShort's 8 tasks have clear dependency relationships:

```
Task 1: Init project           ─┐
Task 2: Database schema          ─┤ Serial (dependent)
                                 │
Task 3: POST /api/shorten        ─┤
Task 4: GET /:code                ─┼─ Parallel (independent)
Task 5: GET /api/stats            ─┤
                                 │
Task 6: Edge cases               ─┤ Depends on 3,4,5
Task 7: Tests                    ─┤ Depends on 3,4,5,6
Task 8: Dockerfile                ─  Independent (parallel with any)
```

Claude generates a Build phase using `pipeline` and `parallel` composition, with `isolation: 'worktree'` for agents that modify files concurrently.

#### pipeline vs parallel: When to Use Which?

| Scenario | Use pipeline | Use parallel |
|----------|-------------|-------------|
| Each item flows through stages independently | Yes | |
| Need all results together before continuing | | Yes |
| Need cross-item dedup/merge | | Yes |
| Maximize wall-clock efficiency | Yes | |
| Stage N needs ALL of stage N-1 complete | | Yes (barrier) |

**Rule of thumb: default to `pipeline`. Only use `parallel` when you need a barrier (cross-item context).**

#### worktree Isolation: When to Use?

`isolation: 'worktree'` runs the agent in an isolated git worktree. Overhead: ~200-500ms + disk.

**Only use when agents modify files in parallel and would conflict.** E.g., Task 3 and Task 4 both modify `src/index.ts` route registration. If agents only read code (e.g., Review), no worktree needed.

#### Parallel Build Timing Comparison

Serial Build (Step 1) vs Parallel Build (Step 4) wall-clock time:

```
Step 1 Serial (1 agent):
  Task1 ─ Task2 ─ Task3 ─ Task4 ─ Task5 ─ Task6 ─ Task7 ─ Task8
  ├─2m──┤─2m──┤─4m──────┤─3m────┤─3m────┤─3m────┤─4m────┤─2m──┤
  Total: ~23 min

Step 4 Parallel (8 agents, 4 concurrent):
  Task1 ─ Task2 ┬ Task3 ──┬ Task6 ─ Task7
                 ├ Task4 ──┤
                 ├ Task5 ──┤
                 └ Task8   │
  ├─2m──┤─2m──┤─4m──────┤─3m────┤─4m────┤
  Total: ~15 min (35% reduction)
```

Total tokens stay roughly the same (same work per task), but wall-clock drops by a third. **Parallelism doesn't save tokens — it saves your waiting time.**

### Step 5: Save and Reuse

After a successful workflow run:

1. Run `/workflows`
2. Select the run
3. Press `s`
4. Choose save location:

| Location | Scope | Path |
|----------|-------|------|
| Project | Everyone who clones the repo | `.claude/workflows/` |
| Personal | Only you, across all projects | `~/.claude/workflows/` |

Next time, invoke directly with `/ldd-linkshort`. Pass arguments via `args`:

```
Run /ldd-linkshort with requirement "online voting system with create poll, vote, and view results"
```

## Hands-on 2: Deep Code Review with a Workflow

Claude Code has `/code-review`, but it's single-agent, single-context. For critical PRs, use a workflow for multi-dimensional review.

### Full Prompt

```
ultracode: Review all changes on this branch vs main.

Review dimensions (one independent agent each):
1. Correctness: logic errors, edge cases, type safety
2. Security: OWASP Top 10, injection, auth, sensitive data
3. Performance: complexity, N+1 queries, memory, caching
4. Maintainability: naming, abstraction levels, duplication, test coverage

Each dimension outputs structured findings:
{ file, line, severity, description, suggestion }

Each finding adversarially verified (3-vote, keep if 2/3 confirm).
Generate a merged report sorted by severity, write to docs/deep-review.md.
```

### Generated Script (Key Parts)

```javascript
const FINDING_SCHEMA = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' },
          line: { type: 'number' },
          severity: { enum: ['blocker', 'warning', 'nit'] },
          dimension: { type: 'string' },
          description: { type: 'string' },
        },
        required: ['file', 'line', 'severity', 'dimension', 'description'],
      },
    },
  },
}

// Phase 1: Four-dimension parallel review
phase('Review')
const reviews = await parallel(
  DIMENSIONS.map(d => () =>
    agent(`Run git diff main...HEAD. ${d.prompt}`, {
      label: `review:${d.key}`, phase: 'Review', schema: FINDING_SCHEMA,
    })
  )
)

// Phase 2: Adversarial verification
phase('Verify')
const verified = await pipeline(allFindings,
  f => parallel(Array.from({ length: 3 }, (_, i) => () =>
    agent(`Try to refute this finding. Default stance: "this is not a problem."
           Finding: ${f.description} (${f.file}:${f.line})`,
      { label: `verify${i}:${f.file}`, schema: VERDICT_SCHEMA })
  )).then(votes => ({
    ...f,
    confirmed: votes.filter(Boolean).filter(v => !v.refuted).length >= 2,
  }))
)
```

**Note the `schema` parameter:** pass a JSON Schema to force structured output from subagents. No text parsing needed — the runtime validates at the tool-call layer and auto-retries on mismatch. This replaces Post 07's fragile `extract_verdict()` function that used `grep` to parse agent text.

### Output Example

```markdown
## Deep Review Report

### Blockers (2)
| # | Dimension | File:Line | Description | Votes |
|---|-----------|-----------|-------------|-------|
| 1 | security | src/routes/shorten.ts:12 | No URL protocol validation | 3/3 confirmed |
| 2 | correctness | src/routes/shorten.ts:28 | Same URL should return same code | 3/3 confirmed |

### Warnings (3)
| # | Dimension | File:Line | Description | Votes |
|---|-----------|-----------|-------------|-------|
| 3 | performance | src/routes/redirect.ts:15 | Sync click recording blocks redirect | 3/3 confirmed |
| 4 | performance | src/routes/stats.ts:8 | COUNT(*) uncached | 2/3 confirmed |
| 5 | security | src/routes/redirect.ts:8 | Open redirect | 2/3 confirmed |

### Filtered False Positives (2)
| # | Finding | Filter Reason |
|---|---------|---------------|
| 6 | Math.random() predictable | 2/3 refuted: short codes are public |
| 7 | Missing rate limiting | 2/3 refuted: acceptable for MVP |

Stats: 7 findings → 5 confirmed + 2 filtered
```

### When Is 5-10x Tokens Worth It?

- **PR > 500 lines**: single agent's context pressure leads to lazy skipping
- **Auth/payment/PII code**: security dimension needs dedicated deep checks
- **Junior dev code merging into core**: maintainability review most valuable
- **Pre-release final gate**: low false positives matter more than full coverage

Daily 5-50 line PRs → `/code-review` is sufficient.

| Dimension | /code-review | Workflow Deep Review |
|-----------|-------------|---------------------|
| Agents | 1 | 4 review + N×3 verify |
| Context | Shared (compaction loses detail) | Independent per agent |
| Output | Free text | Structured Schema |
| False positive rate | Higher | Lower (filtered 2/7 in example) |
| Token usage | Low (~20k) | High (~150-200k) |
| Wall-clock | ~3 min | ~8 min (parallelism offsets agent count) |
| Best for | Daily PRs | Critical releases, security-sensitive code |

## Hands-on 3: Codebase Exploration with a Workflow

Joining a large codebase, need the full picture fast. No adversarial verification needed here — no right/wrong, just information gathering. Core pattern: **Fan-out-and-synthesize**.

### Full Prompt

```
ultracode: I just joined this project. Help me understand the codebase architecture.

Phase 1 — Parallel exploration:
Launch one agent per top-level subdirectory under src/, each independently analyzes:
- Core responsibility (one sentence)
- Key files (with one-line descriptions)
- Exported interfaces (functions/classes/routes)
- Dependencies on other directories
- Design patterns used
- Code stats (file count + line count)

Phase 2 — Synthesis:
Merge all agent analyses into ARCHITECTURE.md:
- System overview (one paragraph)
- Module dependency graph (Mermaid diagram)
- Entry points and request flow
- Tech stack inventory
- Architectural issues (circular deps, tight coupling)
```

### Output Example (ARCHITECTURE.md excerpt)

```markdown
## System Overview

LinkShort is a URL shortener built on Node.js + Hono + SQLite.
4 core modules, ~800 lines, layered architecture (routes → services → data access).

## Module Dependencies

​```mermaid
flowchart TD
    routes --> db
    routes --> utils
    db --> schema
    utils -.-> db
​```

## Module Inventory

| Module | Responsibility | Files | Lines | Deps |
|--------|---------------|-------|-------|------|
| routes/ | HTTP request handling | 3 | 210 | db, utils |
| db/ | Data access layer | 2 | 150 | schema |
| utils/ | Helpers (code gen, URL validation) | 2 | 80 | — |
| config/ | Configuration management | 1 | 40 | — |

## Architectural Issues
- ⚠️ utils/ directly imports db/, violating layered architecture
- ✅ No circular dependencies
- ✅ No orphan modules
```

### Continuous Maintenance with /loop

Exploration isn't a one-time event. Codebases change daily:

```
/loop 30m ultracode: Check git changes in the last 30 minutes.
If files or directories changed, update the affected modules in ARCHITECTURE.md.
If no changes, output "no changes."
```

## Hands-on 4: Session Experience Mining

A powerful use case from Anthropic's blog: **mine your past Claude Code sessions for recurring correction patterns and distill them into CLAUDE.md rules.**

```
ultracode: Analyze my last 50 Claude Code sessions for recurring corrections.

Phase 1 — Mining:
Parallel-analyze each session transcript, extract:
- Places where I rejected Claude's output ("no", "revert", "don't do that")
- Places where I added constraints ("remember to...", "don't forget...")
- Patterns appearing 2+ times

Phase 2 — Clustering:
Group all corrections by theme (naming, architecture, testing, security, style...)

Phase 3 — Verification:
For each candidate rule, adversarially verify:
"Would this rule in CLAUDE.md have prevented a real past mistake?"
Keep only rules that pass.

Phase 4 — Output:
Write confirmed rules to a CLAUDE.md patch suggestion, sorted by priority.
```

This is **Loop-until-done + Adversarial Verify** combined. Session count varies, and clustered rules need adversarial verification to confirm real value.

## Advanced Tips

### Tip 1: Schema-Driven Structured Output

The `schema` parameter forces subagents to return structured data via a StructuredOutput tool call. Format mismatches auto-retry at the tool layer — no text parsing needed. This replaces Post 07's fragile `grep`-based `extract_verdict()`.

### Tip 2: Dynamic Depth with budget

```javascript
const bugs = []
while (budget.total && budget.remaining() > 50000) {
  const result = await agent('Scan for bugs...', { schema: BUGS_SCHEMA })
  if (result.bugs.length === 0) break
  bugs.push(...result.bugs)
  log(`Found ${bugs.length}, ${Math.round(budget.remaining()/1000)}k remaining`)
}
```

Set budget: `ultracode: audit security. Budget 100k tokens.`

Always guard with `budget.total` — without a budget set, `remaining()` returns `Infinity`.

### Tip 3: agentType for Specialized Agents

```javascript
const analysis = await agent('Analyze auth flow', { agentType: 'Explore' })
const review = await agent('Review auth security', { agentType: 'code-reviewer' })
```

### Tip 4: /goal + /loop + Workflow

```
/goal Zero blocker-level security issues in the codebase
/loop 1h ultracode: Scan codebase security, adversarially verify, fix confirmed blockers.
```

### Tip 5: Nested Workflows

```javascript
const research = await workflow('deep-research', 'best practices for short code generation')
await agent(`Implement based on research: ${JSON.stringify(research)}`)
```

One level of nesting only.

## Performance and Cost

![Shell Orchestration vs Dynamic Workflows](../assets/img/08-cost-comparison.svg)

### Constraints

| Parameter | Value | Note |
|-----------|-------|------|
| Max concurrency | 16 agents | Fewer on limited CPU cores |
| Max per run | 1,000 agents | Prevents runaway loops |
| Model selection | Per agent | `{ model: 'opus' }` |
| Worktree isolation | Per agent | `{ isolation: 'worktree' }` |
| Recoverability | Within same session | Completed agents return cached results |

### Budget Control

Set token budget in your prompt:

```
ultracode: audit code security. Budget 50k tokens.
```

### Cost Comparison (LinkShort LDD, estimated)

| Approach | Agents | Est. Tokens | Est. Cost | Wall-Clock |
|----------|--------|-------------|-----------|------------|
| Manual prompt (Post 04) | 5 interactions | ~100k | ~$0.50 | ~50 min (inc. human) |
| Shell orchestration (Post 07) | 5 `claude -p` | ~120k | ~$0.60 | ~40 min (automated) |
| DW basic (Step 1) | 5 agents | ~130k | ~$0.65 | ~35 min |
| DW adversarial (Step 3) | 17 agents | ~300k | ~$1.50 | ~25 min |
| DW parallel Build (Step 4) | 12+ agents | ~350k | ~$1.75 | ~18 min |

**Core trade-off: more tokens for less wall-clock time and higher result trustworthiness.**

## When Not to Use Workflows

| Scenario | Why Not | Use Instead |
|----------|---------|-------------|
| Simple bug fix | Single agent handles it in one pass | Direct prompt |
| Few-line edit in one file | Orchestration overhead > task itself | Direct prompt |
| Routine PR review | `/code-review` suffices | `/code-review` |
| Quick Q&A | No parallelism needed | Direct prompt |

**Decision heuristic: "Does this task need multiple independent perspectives?"** If no, skip the workflow.

## Counter-Intuitive Conclusions

> **The value of Dynamic Workflows isn't "more agents" — it's "more trustworthy results."**

Most people's first reaction: "Workflows just run more agents in parallel for speed." Wrong. **Parallelism is the means; the goal is structurally eliminating single-agent cognitive bias.** One agent reviewing 50 files versus five agents each reviewing 10 files uses roughly the same total tokens — but the latter won't lazily skip the last 15 files due to context length. Adversarial verification isn't about "more eyes" — it's about **agents challenging each other** — something no single-agent architecture can achieve.

More counter-intuitive: **Prompting is more important now, not less.** In Post 07, you wrote Shell scripts — you precisely controlled every step. In Dynamic Workflows, you describe orchestration intent in natural language, and Claude translates it to JS. If your description is vague ("review the code"), Claude generates single-agent review. If precise ("three-angle adversarial verification, keep if 2/3 confirm"), Claude generates real adversarial structure. **You no longer write Bash, but you write "the prompt that makes Claude write Bash" — you're the harness of the harness designer.** This is yet another recursion of Post 01's insight: "from writing prompts to writing systems that generate prompts."

Most counter-intuitive: **Dynamic Workflows are Loop Engineering's endgame — from "you write loops" to "Claude writes loops."** Post 01's core insight was "transfer the prompter role from humans." Post 04 applied it to full lifecycle (five-phase LDD). Post 07 automated LDD orchestration with Shell. Post 08 (this one) hands the orchestration itself to Claude. The evolution is clear:

```
Manual prompt → Shell script orchestration → Dynamic Workflows
(You prompt Agent)  (You write system to      (Claude writes system to
                     prompt Agent)              prompt Agent)
```

Each step hands one more layer of control to automation. But note: **you remain the decision-maker — you decide "how many review dimensions," "which patterns to use," "when to require adversarial verification."** Claude executes your decisions, but the decisions remain yours. The Loop Engineer role hasn't disappeared — the leverage ratio just increased by another order of magnitude.

---

## Diagrams

1. ![Dynamic Workflows Architecture](../assets/img/08-architecture.svg)
2. ![Six Orchestration Patterns](../assets/img/08-six-patterns.svg)
3. ![Shell Orchestration vs Dynamic Workflows](../assets/img/08-cost-comparison.svg)

---

Reading map: [reading-map.md](../reading-map.md)
Previous: [07 Model Orchestration](./07-model-orchestration.md)
