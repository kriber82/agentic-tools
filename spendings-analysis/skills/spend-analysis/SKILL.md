---
name: spend-analysis
description: Use when the user asks to analyze Claude Code AI spend / token cost — where the money goes, cache efficiency, model mix, subagent cost, per-tool cost, or which behaviors to change to spend less. Reads ~/.claude/session-logs + transcripts.
---

# AI spend analysis

Playbook for analyzing personal Claude Code spend from local logs. Graduated from the
2026-07-06 analysis (`docs/superpowers/specs/2026-07-06-ai-spend-analysis.md` in the
repo where it was first run, if present).

## Before you start: the re-analysis guard

Do **not** re-analyze an already-covered window. Check the marker first:

```bash
cat ~/.claude/session-logs/.analyzed-through
```

It records the covered date window + the session id where the **new log schema**
(`assistant_turn.model`, `tool_start.label`, `session_start`) begins. Start your
analysis **after** that boundary; summarize prior periods from the existing spec rather
than recomputing. When done, update the marker (and any baseline note you keep).

## Data sources

- **`~/.claude/session-logs/*.jsonl`** — the custom session-activity logger. Events:
  `session_start`, `user_prompt`, `assistant_turn` (has `ts`, `model`, `delta_by_type`
  {input/output/cache_create/cache_read}, `cost_per_token`), `tool_start`/`tool_end`
  (with `label`, `cost_at_start/end`, `cost_delta_tool`), `cost` (statusline cost tap —
  the ONLY place USD is reliably exposed; transcript `costUSD` is often null).
- **`~/.claude/projects/**/*.jsonl`** — raw Claude Code transcripts. Have per-message
  `usage` (token types) and `isSidechain` (subagent vs main) + `/subagents/` paths, but
  **no USD** and no session-logger fields. Use these to recover model attribution and
  the subagent split for periods before the logger schema existed.

## Cost model (relative weights)

USD isn't per-token in the logs, so model cost with Anthropic-style multipliers vs a
base input token: **input 1× / output 5× / cache_create 1.25× / cache_read 0.1×**.
`subagent_cost.py` uses published absolute Opus/Sonnet rates for the downgrade
counterfactual. Cross-check modeled shares against the `cost` events' real USD.

## The scripts (`scripts/`, run with `uv run` or `python3`)

| script | answers |
|---|---|
| `spend_analysis.py` | Top-line: total modeled cost, $/day, per-session, token-type volume vs cost breakdown, blended $/M. **Start here.** |
| `model_attrib.py` | Per-model token spend + first/last timeline from transcripts (catches silent model-routing changes). |
| `cache_miss.py` | Cache-miss signature turns (create > ½ read) + idle-expiry count (>5-min gaps). |
| `cache_waste.py` / `cache_waste2.py` / `cache_waste3.py` | Three independent estimates of the **avoidable** slice of cache_create: floor/HWM (upper bound), per-turn signature (lower bound), and TTL-expiry-attributable (the actionable one). Expect them to bracket ~20–22%. |
| `subagent_cost.py` | Sidechain (subagent) cost by model + Opus→Sonnet savings counterfactual. |
| `cost_by_tool.py` | Attributes cost deltas to the preceding tool completion (rough; only meaningful for slow tools like Agent/TaskOutput). |

Paths are hardcoded to `~/.claude/...` and self-contained (stdlib only).

## Method

1. Run `spend_analysis.py` for the top-line and the token-type volume-vs-cost table.
2. Confirm the model mix with `model_attrib.py` (rule out silent routing changes).
3. Decompose cache cost: `cache_miss.py` + the three `cache_waste*.py` — report the
   avoidable slice as a **range**, and name its dominant driver (usually idle-expiry).
4. `subagent_cost.py` for the subagent share + downgrade opportunity.
5. `cost_by_tool.py` only if a per-tool view is asked for (flag it as approximate).

## What the 2026-07-06 baseline found (context for interpretation)

Context **re-reading** dominates, not output: cache_read ~93% of tokens / ~42% of cost;
cache_create ~6% / ~35%; output ~1% / ~22%. **Cost per session tracks context size, not
turn count.** Only ~21–22% of cache_create is avoidable (TTL misses after >5-min idle) —
the cache is otherwise healthy (11–15:1 read:create). Subagents are ~6% of spend but
~44% of subagent turns ran on Opus (inheriting the parent). The controllable levers:
smaller/fresher context, Sonnet where it suffices, no idle cache-expiry, read-only
subagents on Sonnet — see `~/.claude/cost-awareness.md`.

## Deliverable shape

Structure findings as: **1) Cost insights**, **2) Improvement suggestions (nudges/
behaviors)**, **3) Tracking & analysis improvements**. Ground each claim in a number
from the scripts, and give avoidable-cost figures as ranges (multiple estimators),
never a single false-precision number.
