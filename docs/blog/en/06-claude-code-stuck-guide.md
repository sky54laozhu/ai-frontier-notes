---
title: 'When Claude Code Freezes — Six Root Causes and a Practical Troubleshooting Playbook'
slug: 06-claude-code-stuck-guide
date: 2026-06-10
series: ai-frontier-notes
series_index: 6
keywords: [Claude Code, freeze, stuck, troubleshooting, Stream timeout, token stall, recovery]
prev: 05-token-optimization
canonical: https://github.com/sky54laozhu/ai-frontier-notes/blob/main/docs/blog/en/06-claude-code-stuck-guide.md
---

# When Claude Code Freezes — Six Root Causes and a Practical Troubleshooting Playbook

> The first five posts covered Loop Engineering theory, practice, a Hello World, full-lifecycle LDD, and cost optimization. This post tackles a problem every Claude Code user will eventually face: **the spinner keeps spinning, the clock keeps ticking, but the token count won't budge — Claude Code is stuck.** It's not a single bug — it's at least six different root causes sharing one symptom. This post dissects each one and gives you a diagnosis-to-recovery workflow.

**Jump to:** [Symptom](#symptom-time-passes-tokens-dont) · [Six Root Causes](#six-root-causes) · [Diagnosis Flowchart](#diagnosis-flowchart-2-minutes-to-root-cause) · [Recovery Toolkit](#recovery-toolkit-three-layer-strategy) · [Anti-Pattern Warning](#anti-pattern-warning-letting-claude-fix-itself) · [Prevention Checklist](#prevention-checklist-eight-rules)

## Symptom: Time Passes, Tokens Don't

You're mid-flow with Claude Code when you notice:

- The spinner is still going ("Photosynthesizing…", "Thinking…")
- The clock in the corner keeps ticking: 3m 21s … 5m 00s … 8m 35s
- But the token counter is frozen solid: ↓ 301 tokens … ↓ 301 tokens … ↓ 301 tokens

**The 30-second rule**: If 30 seconds pass with the clock advancing but the token count unchanged, it's almost certainly stuck. Normal "deep thinking" still consumes Thinking Tokens — the number never completely flatlines.

This is one of the most frequently reported issues in the Claude Code community. Over 10 independent GitHub issues describe this exact symptom — with new reports appearing every month from December 2025 through June 2026.

## Six Root Causes

"Stuck" looks the same on the surface, but the underlying causes are completely different. Misdiagnose, and you'll apply the wrong fix.

![Six Root Causes of Claude Code Freezing](../assets/img/06-six-root-causes.svg)

### Cause 1: Stream Idle Timeout (Most Common ★★★)

**Mechanism**: Claude Code receives tokens from the Anthropic API via an HTTP streaming connection (SSE). Normally, tokens flow one after another. But sometimes the stream stalls — the API starts processing but sends no data, or an intermediate gateway (CDN, reverse proxy) silently drops the connection.

**The problem**: Claude Code's HTTP client lacks an effective read timeout in certain scenarios. The connection is technically "alive," but no data flows through it. The client waits — 5 minutes, 15 minutes, even 30 minutes — with no error, no retry, and no feedback to the user.

**Typical signs**:

- Token count completely frozen for 5–30 minutes
- No error messages visible
- Logs may show `ERR_STREAM_PREMATURE_CLOSE` or `AbortError` (but the user doesn't see them)
- Timing appears random with no clear trigger

> **References**: [GitHub #40057](https://github.com/anthropics/claude-code/issues/40057), [#26092](https://github.com/anthropics/claude-code/issues/26092), [#44921](https://github.com/anthropics/claude-code/issues/44921)

### Cause 2: Network Connection Drop (Common ★★☆)

**Mechanism**: The underlying TCP connection dies, but Claude Code's UI layer doesn't know. The spinner keeps spinning, but data will never arrive.

**High-risk environments**:

- **tmux + SSH**: WiFi drops → SSH tunnel breaks → Claude Code's connection inside tmux becomes invalid. The process stays alive (tmux protects it), but the network channel is gone.
- **VPN / Cross-border networks**: VPN reconnection changes IP, invalidating long-lived connections.
- **Corporate proxies**: Enterprise security gateways may kill idle connections after a timeout.

**How it differs from Cause 1**: Cause 1 means the API isn't sending data; Cause 2 means data can't reach you at all. Recovery differs — Cause 2 needs a network check, not patience.

> **References**: [GitHub #25286](https://github.com/anthropics/claude-code/issues/25286)

### Cause 3: Large Tool Output Triggers Connection Reset (Common ★★☆)

**Mechanism**: When Claude instructs Claude Code to execute a tool (e.g., `Glob` returning 90+ file paths, or `Read` on a massive file), the tool execution itself can take a while. During this time, no valid data traverses the API's HTTP connection. If **5 minutes** pass without valid data on the underlying HTTP connection, the OS resets it.

**The problem**: Claude Code doesn't properly catch this connection reset error. The connection is dead, but the UI still shows "working."

**Typical signs**:

- Freeze happens right after a tool call
- Duration is usually around **5 minutes** (OS TCP keep-alive timeout)
- A large-result tool call just completed

> **References**: [GitHub #44921](https://github.com/anthropics/claude-code/issues/44921), [#13240](https://github.com/anthropics/claude-code/issues/13240)

### Cause 4: Context Window Overflow Triggers Auto-Compact Loop (Occasional ★☆☆)

**Mechanism**: Claude Code has an auto-compact mechanism — when context usage hits a threshold (~94%), it automatically compresses conversation history. But if a large file or tool output is read back into context immediately after compression, context inflates again, triggering another compression… creating a loop.

**Typical signs**:

- Occurs late in long sessions (token count near the limit, e.g., 156K/167K)
- Occasional flash of "Compacting…"
- Logs show terminal renderer write buffers surging to 80–87KB/frame
- Deferred message queues of 700–1,170 messages

**Post 05 prevention**: This is exactly why the Token Economics post emphasized "short session strategy" and "proactive `/compact`" — don't wait for the system to auto-compact under pressure.

> **References**: [GitHub #25286](https://github.com/anthropics/claude-code/issues/25286), [#24478](https://github.com/anthropics/claude-code/issues/24478)

### Cause 5: API Server Issues / Model-Specific Degradation (Occasional ★☆☆)

**Mechanism**: Anthropic's API can experience partial degradation — a **specific model** degrades while the rest of the platform is fine. For example, Opus might be heavily queued while Sonnet works perfectly. Your request goes out, sits in a queue, but the server never starts processing.

**Typical signs**:

- Switching models instantly fixes it: `/model sonnet` → working normally
- Other users (or you in a different session on a different model) are fine
- Anthropic's status page may show "Degraded Performance"

> **References**: [status.anthropic.com](https://status.anthropic.com)

### Cause 6: UI Render Ghost Freeze (Mildest)

**Mechanism**: The most harmless but most confusing case. Claude has actually returned the complete result. The API call is finished. But the terminal UI's spinner wasn't cleared. What you see as "stuck" is a rendering bug — the data is already there, just not displayed.

**Typical signs**:

- Pressing Enter or sending any message causes **instant recovery** and starts the next turn
- No "previous response" flash — the response was already complete
- More common after long sessions and large outputs

## Diagnosis Flowchart: 2 Minutes to Root Cause

No guessing needed — follow this decision tree.

![Diagnosis Flowchart](../assets/img/06-diagnosis-flowchart.svg)

**Full steps**:

1. **Wait 30 seconds**, watch whether the token count changes at all
   - Changing → Normal, the model is in deep thinking (especially Opus extended thinking)
   - Static → Continue

2. **Press Enter** or type any text
   - Instant recovery → **UI Ghost Freeze** (Cause 6), no worries
   - No response → Continue

3. **Recall your last action**: Did a large tool call just execute? (Glob many files, Read large file, Bash with long output)
   - Yes → Likely **Large Tool Output** (Cause 3), wait ~5 min or Esc to interrupt
   - No → Continue

4. **Check context usage**: Is the token count near the limit (> 90%)?
   - Yes → Likely **Auto-Compact Loop** (Cause 4), Esc then `/compact` or `/clear`
   - No → Most likely **Stream Timeout** (Cause 1) or **Network Drop** (Cause 2)

5. **If in a tmux/SSH/VPN environment**: Prioritize network checks (Cause 2), try `ping api.anthropic.com` from another terminal

## Recovery Toolkit: Three-Layer Strategy

![Recovery Toolkit](../assets/img/06-recovery-toolkit.svg)

### Layer 1: Immediate Recovery (0–30 seconds)

These are non-destructive and can be tried at any time:

| Action | Command | Best For |
|--------|---------|----------|
| **Probe message** | Press Enter or type text | UI Ghost Freeze |
| **Esc interrupt** | Press `Esc` | All freezes |
| **Resend** | Esc then retype the request | Stream Timeout |
| **Switch model** | `/model sonnet` | Model-specific failure |

**Order of operations**: Enter probe → Esc interrupt → Resend → Switch model. From least to most disruptive.

### Layer 2: Diagnostic Recovery (1–3 minutes)

If immediate recovery fails or the problem recurs:

```bash
# Automated diagnosis
/doctor

# Safe mode (disables all MCP and Hooks)
claude --safe-mode

# Check Anthropic API status
# Open status.anthropic.com in a browser

# Check for problematic config
cat ~/.claude/settings.json | grep -i timeout
```

**Key check**: Whether `settings.json` contains custom timeout environment variables. If so, **delete them** (see "Anti-Pattern Warning" below).

### Layer 3: Prevention (Long-term)

These habits significantly reduce freeze frequency:

1. **Proactive `/compact`**: Don't wait for auto-compact. Manually compress when token usage exceeds 70%.
2. **Short session strategy**: `/clear` after completing a subtask instead of running everything in one mega-session. (Post 05 covers this in depth.)
3. **Avoid reading oversized files**: Files over 25K tokens trigger `MaxFileReadTokenExceededError`. Use `--offset` and `--limit` to read specific portions.
4. **Don't manually set timeout env vars**: Use Claude Code's default timeout configuration.

## Anti-Pattern Warning: Letting Claude Fix Itself

GitHub Issue [#51659](https://github.com/anthropics/claude-code/issues/51659) documents a classic anti-pattern:

> User discovers Claude Code freezing frequently → Asks Claude Code to diagnose the problem → Claude Code adds massive timeout values to `settings.json` → **Freezing gets worse**

Specifically, Claude Code configured itself with:

```json
{
  "env": {
    "CLAUDE_STREAM_IDLE_TIMEOUT_MS": "900000",
    "API_TIMEOUT_MS": "1200000",
    "CLAUDE_CODE_MAX_RETRIES": "10",
    "MAX_THINKING_TOKENS": "12000",
    "CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING": "1"
  }
}
```

**Why this makes things worse**:

- `CLAUDE_STREAM_IDLE_TIMEOUT_MS: 900000` = a **15-minute** tolerance window. Normally Claude Code retries within seconds; now it waits 15 minutes.
- `API_TIMEOUT_MS: 1200000` = a **20-minute** API timeout.
- Other users don't have this problem precisely because they use the defaults.

**Lessons**:

1. **Don't let Claude Code modify its own timeout config.** It doesn't know its own client implementation details and will fabricate plausible-looking but harmful settings.
2. If your `settings.json` has a similar `env` block, **delete it immediately**.
3. Each "self-repair" attempt gets written to Memory, then referenced in future sessions — creating a **positive feedback loop of broken fixes**.

## Prevention Checklist: Eight Rules

| # | Rule | Rationale |
|---|------|-----------|
| 1 | Token static for 30s → confirmed stuck | Normal thinking always consumes tokens |
| 2 | Press Enter first, then Esc | Rule out UI ghost freeze before interrupting |
| 3 | Never manually set timeout env vars | Defaults are tuned for a reason |
| 4 | `/compact` when tokens > 70% | Prevent auto-compact loops |
| 5 | `/clear` after completing a subtask | Short sessions are more stable than mega-sessions |
| 6 | Keep individual files < 25K tokens | Oversized files trigger read errors |
| 7 | tmux/SSH users: add keepalive | `ServerAliveInterval 60` prevents connection drops |
| 8 | Periodically audit `settings.json` env block | Catch leftover bad config |

## Known Progress and Outlook

As of June 2026, Anthropic has improved timeout handling and error recovery across multiple Claude Code releases. But the core issue (no effective retry on stream idle timeout) remains not fully resolved — new reports appear on GitHub monthly.

Community consensus:

- **This is a client-side issue**, not an API issue — the client should error and retry on timeout, not wait silently
- **The most effective mitigation is user-side habits** — short sessions, proactive compacts, hands off timeout config
- **Anthropic's team is aware** — multiple related issues are marked as duplicates pointing to core tracking issue [#25979](https://github.com/anthropics/claude-code/issues/25979)

---

**This is a practical troubleshooting manual. Next time Claude Code freezes, flip to the "Diagnosis Flowchart" — 2 minutes to root cause, then apply the right fix.**

---

## References

- [Claude Code Troubleshooting — Official Docs](https://code.claude.com/docs/en/troubleshooting)
- [GitHub #44921 — Hangs with zero token consumption for 25-30 min](https://github.com/anthropics/claude-code/issues/44921)
- [GitHub #51659 — Freezes mid-response with zero token raise](https://github.com/anthropics/claude-code/issues/51659)
- [GitHub #26092 — Hangs without updating token usage](https://github.com/anthropics/claude-code/issues/26092)
- [GitHub #25286 — 100% write ratio in terminal renderer](https://github.com/anthropics/claude-code/issues/25286)
- [GitHub #12226 — Freezes with token consumption but no progress](https://github.com/anthropics/claude-code/issues/12226)
- [GitHub #40057 — Hangs with stagnant token usage until retry](https://github.com/anthropics/claude-code/issues/40057)
- [GitHub #31781 — Hangs with no token consumption](https://github.com/anthropics/claude-code/issues/31781)
- [GitHub #13240 — Hangs indefinitely during processing](https://github.com/anthropics/claude-code/issues/13240)
- [GitHub #24478 — CLI freezes requiring SIGKILL](https://github.com/anthropics/claude-code/issues/24478)
- [GitHub #20430 — Stuck in working state with 0 tokens](https://github.com/anthropics/claude-code/issues/20430)
