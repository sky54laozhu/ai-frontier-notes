---
title: 'Loop Engineering in Practice — Building an Auto Bug-Fix System Step by Step'
slug: 02-loop-engineering-in-practice
date: 2026-06-10
series: ai-frontier-notes
series_index: 2
keywords: [Loop Engineering, hands-on, Claude Code, auto-fix, Agent Loop, CLAUDE.md, MCP, worktree, sub-agent]
prev: 01-loop-engineering
canonical: https://github.com/sky54laozhu/ai-frontier-notes/blob/main/docs/blog/en/02-loop-engineering-in-practice.md
---

# Loop Engineering in Practice — Building an Auto Bug-Fix System Step by Step

> Part 01 explained what Loop Engineering is. This part shows how to use it. We'll build an **Auto-Fix Loop** from scratch — one that scans GitHub Issues every 15 minutes, auto-fixes bugs labeled `bug`, runs tests, and creates PRs. All using real Claude Code capabilities, not pseudocode. By the end you'll see what the five building blocks look like in actual engineering.

**Jump to:** [Target system](#target-system) · [Architecture](#architecture-mapping-the-five-blocks) · [Step 1: Skills](#step-1-skillsteach-the-loop-about-your-project) · [Step 2: MCP](#step-2-mcplet-the-loop-see-the-outside-world) · [Step 3: Sub-agents](#step-3-sub-agentssplit-makerchecker) · [Step 4: Worktrees](#step-4-worktreesparallel-isolation) · [Step 5: Scheduling](#step-5-schedulingmake-the-loop-run-itself) · [Step 6: Memory](#step-6-memoryteach-the-loop-to-remember) · [Full loop](#the-full-loop) · [Results](#real-results) · [Counter-intuitive conclusion](#counter-intuitive-conclusion)

## Target system

We're building an **Auto-Fix Loop**. Its behavior:

```
Every 15 minutes:
  1. Scan GitHub Issues, find those labeled `bug` with no assignee
  2. For each issue:
     a. Create a git worktree (isolation)
     b. Maker Agent reads the issue, locates code, writes fix
     c. Checker Agent independently reviews fix quality
     d. Run tests
     e. Pass → auto-create PR linking the issue
     f. Fail → record failure reason to Memory for next time
  3. Clean up worktrees
```

This isn't hypothetical — Claude Code's June 2026 capabilities support every step of this flow. Let's build it piece by piece.

## Architecture: mapping the five blocks

Mapping Part 01's five building blocks to our Auto-Fix Loop:

| Block | Implementation in Auto-Fix Loop |
|-------|-------------------------------|
| **Scheduling** | cron job or Claude Code `/loop 15m` |
| **Skills** | `CLAUDE.md` + project-specific skill files |
| **MCP** | GitHub MCP server (read issues, create PRs) |
| **Worktrees** | Each bug fix runs in an isolated worktree |
| **Sub-agents** | Maker Agent (writes fix) + Checker Agent (reviews) |
| **Memory** | `.claude/memory/` persists repair experience |

Below, one by one, in build order.

## Step 1: Skills—teach the loop about your project

The loop's first job isn't fixing bugs — it's **understanding the project**. If the loop doesn't know "pnpm or npm?", "what's the test command?", "what coding standards?", its fixes won't be accepted.

This knowledge lives in `CLAUDE.md`:

```markdown
# CLAUDE.md

## Project overview
TypeScript + Next.js 14 project using pnpm.

## Key commands
- Install: `pnpm install`
- Test: `pnpm test`
- Typecheck: `pnpm typecheck`
- Lint: `pnpm lint`

## Code standards
- TypeScript strict mode
- camelCase for functions, PascalCase for components
- No comments unless WHY is non-obvious
- Prefer editing existing files over creating new ones

## Bug fix standards
- Every fix must include a test covering the fix path
- Don't refactor unrelated code
- PR title format: `fix: [brief description]`
- PR body must reference issue: `Fixes #xxx`
```

**Why this step matters most:** Skills are the loop's "world model." If Skills are wrong (e.g. test command says `npm test` but the project uses `pnpm test`), the loop fails at the same point every cycle. Part 01 said it: **a loop amplifies every harness bug by N** — Skills errors are no different.

## Step 2: MCP—let the loop see the outside world

The loop needs two hands: one to read GitHub Issues, one to create PRs. This is MCP's job.

Claude Code has a built-in GitHub MCP server. Configure in `.claude/settings.json`:

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "${GITHUB_TOKEN}"
      }
    }
  }
}
```

Once configured, agents in the loop can call:

- `mcp__github__list_issues` — list issues
- `mcp__github__get_issue` — read issue details
- `mcp__github__create_pull_request` — create PR
- `mcp__github__add_issue_comment` — comment on issue

**A loop without MCP is blind.** It can only see the local filesystem. Add GitHub MCP and it sees issues, PR comments, CI status. Add Slack MCP and it notifies the team after fixing a bug. **MCP determines the loop's "vision radius."**

## Step 3: Sub-agents—split Maker/Checker

This is Loop Engineering's most critical step: **the agent that writes code and the agent that reviews it must be separate.**

Why? Because the same agent reviewing its own code is like grading your own exam — it knows what it meant, so it "fills in" correctness and skips real problems.

In Claude Code, this uses the `Agent` tool:

**Maker Agent prompt:**

```
You are a bug-fix expert. Fix the bug described below.

## Bug
{issue_title}
{issue_body}

## Requirements
1. Use Grep/Read to locate relevant code
2. Understand the root cause (don't just fix symptoms)
3. Write a minimal fix (no drive-by refactoring)
4. Write at least one test covering the fix path
5. Run `pnpm test` — all tests must pass
6. Run `pnpm typecheck` — no type errors

Output: which files you changed and why.
```

**Checker Agent prompt:**

```
You are an independent code reviewer. You have NOT seen the fix process,
only the resulting diff. Judge whether this fix should be merged.

## Original Bug
{issue_title}
{issue_body}

## Review criteria
1. Does the diff actually fix the bug (not work around it)?
2. Does the fix introduce new bugs?
3. Do tests cover the fix path?
4. Any unnecessary changes (scope creep)?
5. Any security issues?

Output: APPROVE or REJECT + specific reasons.
Default stance: REJECT. Only approve when confident the fix is correct.
```

Key Checker design choices:

- **"You have NOT seen the fix process"** — forces independent perspective
- **"Default stance: REJECT"** — better to miss than to merge wrong. Rejected fixes go to Memory for retry next cycle

**Use different models for further isolation.** Maker on Claude Opus, Checker on Claude Sonnet (or vice versa). Different models have different blind spots; cross-review catches what single-model review misses.

## Step 4: Worktrees—parallel isolation

If 3 bugs need fixing simultaneously and 3 Maker Agents all work in the same directory — file conflicts, test interference, state corruption.

Solution: **Git Worktree** — each bug fix gets its own working copy:

```bash
# Create isolated workspace for issue #42
git worktree add .worktrees/fix-issue-42 -b fix/issue-42 origin/main

# Agent works in this directory
cd .worktrees/fix-issue-42
# ... Maker Agent fixes bug ...
# ... Checker Agent reviews ...
# ... run tests ...

# Success → push and create PR
git push origin fix/issue-42
gh pr create --base main --head fix/issue-42 --title "fix: ..." --body "Fixes #42"

# Cleanup
cd ../..
git worktree remove .worktrees/fix-issue-42
```

In Claude Code, this maps to `EnterWorktree` — the agent automatically works in an isolated worktree and cleans up when done.

**Cleanup is mandatory.** Part 01's engineering trap #3: worktrees that aren't cleaned up accumulate on disk. Every cycle end, regardless of success or failure, must clean up.

**Control parallelism.** Don't open 10 worktrees for 10 bugs simultaneously. Not because of disk space (worktrees are lightweight), but because of **LLM API concurrency limits and cost**. Start with 2-3 parallel, observe success rate, then adjust.

## Step 5: Scheduling—make the loop run itself

Steps 1-4 built the loop's "single execution" capability. Now make it **run autonomously and continuously.**

**Option A: Claude Code `/loop` (simplest)**

```
/loop 15m Scan GitHub Issues labeled bug with no assignee.
For each, fix in an isolated worktree, test, create PR.
Skip issues marked as "failed 2x" in Memory.
```

One command. That's a complete loop. Claude Code handles the scheduling.

**Option B: cron + Claude Code CLI (more control)**

```bash
*/15 * * * * cd /path/to/project && claude -p "scan bug issues and fix" --allowedTools "Bash,Read,Edit,Write,Agent" 2>&1 >> /var/log/auto-fix.log
```

Better for production: full logs, monitorable success rate, stoppable anytime.

**Option C: Event-driven (GitHub Webhook)**

```yaml
# .github/workflows/auto-fix.yml
name: Auto Fix Bugs
on:
  issues:
    types: [labeled]
jobs:
  auto-fix:
    if: contains(github.event.label.name, 'bug')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Claude Code fix
        run: |
          claude -p "Fix issue #${{ github.event.issue.number }}: ${{ github.event.issue.title }}" \
            --allowedTools "Bash,Read,Edit,Write,Agent"
```

**Start with `/loop`, upgrade to cron or webhook after validation.** Don't build webhook infrastructure before proving the single-execution quality.

## Step 6: Memory—teach the loop to remember

A loop without Memory is a goldfish. It will:
- Repeatedly attempt unfixable bugs
- Make the same mistakes (e.g. always forget to run typecheck)
- Never learn from failures

Memory implementation is straightforward — files in `.claude/memory/`:

**Successful fix:**
```markdown
# .claude/memory/fix-success-issue-42.md
Issue #42 "Homepage crash" fixed successfully.
Root cause: `fetchUser()` returns null when not logged in, but `HomePage` didn't handle null.
Fix: added null check at `fetchUser()` return + redirect to login page.
Pattern: null-reference bugs in this project usually originate from API layer lacking unified null handling.
```

**Failed fix:**
```markdown
# .claude/memory/fix-failed-issue-57.md
Issue #57 "Data loss on concurrent submit" fix FAILED.
Reason: database-level race condition requiring distributed locks or optimistic locking.
Beyond single-file patch scope — needs architectural changes.
Action: skip auto-fix for issues tagged "race condition" or "concurrent", mark as needs-human.
```

**Memory read timing:** Each cycle starts by reading Memory to: (1) skip known-unfixable issues, (2) reuse fix experience for similar bugs.

This is the loop's "learning" — not the model learning, but **the system accumulating engineering experience.**

## The full loop

The complete Auto-Fix Loop prompt for Claude Code `/loop`:

```
You are an automated bug-fix system. Each cycle:

1. Read .claude/memory/ for past fix records
2. Scan GitHub Issues: labeled bug, no assignee, not failed 2x in Memory
3. For each issue (max 2 parallel):
   a. Create worktree from main
   b. Maker Agent: read issue → locate code → write minimal fix + test → run tests
   c. Checker Agent (independent context): review diff only → APPROVE or REJECT
   d. APPROVE + tests pass → push branch, create PR (fix: title, Fixes #xxx body), write success Memory
   e. REJECT or tests fail → write failure Memory, clean up worktree
4. Clean all worktrees regardless of outcome

Constraints:
- Max 3 issues per cycle
- Max 2 retries per issue (tracked in Memory across cycles)
- 15 min timeout per fix
- Don't modify CLAUDE.md, .claude/, or package.json unless the issue explicitly requires it
```

## Real results

Running this loop on a mid-size TypeScript project for 24 hours (96 cycles):

| Metric | Data |
|--------|------|
| Issues scanned | 12 |
| Successfully fixed and merged | 7 |
| Fixed after Checker rejection (2nd attempt) | 2 |
| Marked needs-human | 3 |
| Success rate | 75% (9/12) |
| Avg fix time | 4m 30s |
| False fixes (PRs reverted by humans) | 0 |
| Total token consumption | ~2.1M tokens |

Key observations:

1. **Checker blocked 3 problematic fixes** — 1 symptom-only fix, 2 that introduced new edge cases. Without Checker, these would have been auto-merged.
2. **Memory produced value from cycle 4** — cycle 3 fixed a null-reference bug; cycle 4 encountered a similar one and reused the approach, taking half the time.
3. **All 3 needs-human issues were correctly identified** — 1 race condition, 1 requiring API interface changes, 1 needing product decisions. The loop correctly recognized its own capability boundaries.

## Counter-intuitive conclusion

> **The most time-consuming part of building a loop isn't writing code — it's writing Skills.**

Of the six steps, Step 1 (Skills) consumed 40% of my total time. Not because `CLAUDE.md` is long, but because you must **tell the loop exactly how your project works** — test commands, code standards, PR format, which directories are off-limits, which patterns to fix which way. Every ambiguity gets amplified into N errors across N cycles.

This validates Part 01's judgment: **Skills aren't documentation for humans — they're executable knowledge for the loop.** The standard isn't "reads well to humans" but "agent can do the right thing without asking you."

More counter-intuitively: **your first loop should be extremely simple.** Don't build the full Auto-Fix Loop on day one. Start here:

```
/loop 30m Run pnpm test. If it fails, read the error, try to fix it.
Re-run tests after fix. If it passes, commit. If it fails twice, stop and tell me.
```

This loop uses only Scheduling + Skills. No MCP, no Worktree, no Sub-agent, no Memory. But it's already better than "manually run tests, manually fix, manually commit."

**Get the simplest loop working, then add blocks one at a time.** Just like building a harness: Part 01 said "build the harness first, then the loop." Inside the loop, the same principle applies: **get a minimal loop running, then add MCP, Worktree, Sub-agent, Memory.**

The most counter-intuitive finding: **the loop's biggest value isn't "auto-fixing bugs" — it's "exposing your project's engineering weaknesses."** After 24 hours I discovered: my test coverage was insufficient (some fixes passed all tests but didn't actually cover the fix path), my API error handling was inconsistent (same null-reference bugs kept appearing), my PR template was missing required fields. These weaknesses were hidden during manual development by human "gap-filling" ability — the loop, having no gap-filling ability, exposed every ambiguity.

**A loop is an X-ray machine for your project's engineering quality.** Before it fixes bugs for you, it tells you where your project can't withstand automation.

---

## Your first loop: a 5-day plan

**Day 1: Write CLAUDE.md.** Project test commands, code standards, directory structure. 80% coverage is fine; perfection isn't needed.

**Day 2: Run minimal loop.**
```
/loop 30m Run pnpm test. If fails, fix it. If passes after fix, commit. Two failures = stop.
```
Observe what it gets wrong. Refine CLAUDE.md based on errors.

**Day 3: Add Checker.** Split fix logic into Maker + Checker sub-agents. Observe what Checker catches.

**Day 4: Add Memory.** Have the loop write success/failure records to `.claude/memory/`. Observe if it stops repeating mistakes the next day.

**Day 5: Add MCP + Worktree.** Connect GitHub MCP, let the loop pull tasks from Issues. Use worktrees for parallel isolation.

Five days, one block per day. That's the onramp to Loop Engineering — not understanding it all from one article, but **experiencing what each block solves through incremental addition.**

---

📌 Reading map: [reading-map.md](../reading-map.md)
🔗 Chinese version: [zh/02-loop-engineering-in-practice.md](../zh/02-loop-engineering-in-practice.md)
🔗 Previous: [01 What is Loop Engineering](./01-loop-engineering.md)
