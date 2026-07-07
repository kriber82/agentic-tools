# AI spend analysis & logger improvements — findings + handoff

**Date:** 2026-07-06
**Data analyzed:** `~/.claude/session-logs/*.jsonl` (cost-logged window) plus raw
transcripts `~/.claude/projects/**/*.jsonl` (a longer history predating cost logging).
**Analyzed-through marker:** all historical logs up to `2026-07-06`. The current
session (`<session-B>`) onward carries the **new schema** (see below) and is the
starting point for the *next* analysis — see the `.analyzed-through` marker file to
avoid re-analyzing the same window.

Analysis scripts (scratch, gitignored): `tmp/spend_analysis.py`,
`tmp/model_attrib.py`, `tmp/cache_miss.py`, `tmp/subagent_cost.py`,
`tmp/cost_by_tool.py`. To be graduated into a skill (pending #4).

---

## 1. Cost insights

- **Within the cost-logged window you run ~100% `claude-opus-4-8`.** (The
  `opus-4-7 → opus-4-8` switch was 2026-06-18, *before* cost logging began
  2026-06-23, so the cost data is model-continuous. Only discontinuity in-window
  is the weekend silence 07-03 19:41 → 07-06.)
- **Context re-reading is THE driver, not output.** Token volume vs modelled cost
  (weights in=1× / out=5× / cache-write=1.25× / cache-read=0.1×):

  | type | % volume | ~% cost |
  |---|---:|---:|
  | cache_read | 92.7% | 42.1% |
  | cache_create | 6.1% | 34.6% |
  | output | 1.0% | 22.4% |
  | input | 0.2% | 0.9% |

  Blended cost per token is low *because* 93% is cache reads, but that cache-read
  volume still makes it the #1 cost line. Every turn re-reads the whole cached
  prefix; **long-lived large-context sessions are the core cost.** A notable share
  of individual turns re-read very large (>5 M token) cached prefixes.
- **Cost per session tracks context size, not turn count.** Expensive-per-turn
  sessions are *few big turns over a bloated context* (e.g. `<session-A>`: a handful
  of turns each re-reading a huge cached prefix — high $/turn driven by context size,
  not turn count).
- **How much of the cache-write cost is an ACTUAL (avoidable) miss? ≈ 21–22%.** The
  rest is legitimate first-write + normal re-writing of the un-sealed conversation
  tail between cache breakpoints. Two independent estimates agree: cold-turn
  signature (create > ½ read) = 21%; post-gap re-creation (cache_create on the
  requests following a >5-min gap) = 22%. A naive high-water-mark model says 88% but
  that's an upper bound — it miscounts normal tail churn as misses. Cache is actually
  healthy (11–15:1 read:create). Write-side only (a miss re-prices tokens
  0.1×→1.25×). **Almost all of the avoidable slice is the 26% of prompts that follow
  a >5-min idle** → the exact target of the idle-timer / cache-cooling nudge (#1/#3).
  Scripts: `tmp/cache_waste*.py`.
- **Re-caching (only ~21–22% of it avoidable — see above).** cache_create is
  34.6% of cost from 6% of tokens — re-paid at 1.25× (vs 0.1× read, a ~12.5× spike)
  whenever the prefix grows or **expires**. Drivers:
  - **Idle-expiry (biggest behavioral lever): ~26% of prompts followed a
    >5-min idle gap** (median gap 2.7 min, p90 9.1 min). The 5-min ephemeral-cache
    TTL lapses → next turn re-pays full cache-create.
  - **~11% of turns carry a cache-miss signature** (cache_create > ½
    cache_read).
  - Blended-rate spikes confirm it: individual re-cache-dominated sessions spike to
    many times (~10–40×) the floor blended rate.
- **Subagents are NOT a cost driver (~6% of spend).** But **~44% of subagent
  turns run on Opus** (the rest on Sonnet). Moving
  Opus subagent turns → Sonnet saves ~80% of that slice ≈ **3.9% of total**. Free
  quality-wise for Explore / review / search agents. Root cause: general-purpose /
  Explore / superpowers agents **inherit the parent model (opus-4-8)**; only the
  nWave `*-reviewer` agents pin Haiku.
- **Per-tool cost spikes (retrospective, rough).** Baseline per-completion is flat
  for Bash/Edit/Read (they rank high only by *frequency*). Real spikes vs that
  baseline: **Agent ~3.5×, TaskOutput ~3×, AskUserQuestion ~1.8×** — Agent
  = subagent context spin-up; the interactive-pause tools spike because a >5-min
  idle (→ cache expiry) often follows them.

## 2. Improvement suggestions (nudges & behaviors)

Status-line / hook nudges (PENDING — build in fresh session):
- **Idle timer in status line (#1).** `now − last_assistant_turn_ts`. Doubles as a
  cache-expiry predictor: dim <3 min, **warn ≥5 min** ("cache cooling"). Data is
  available — statusline stdin has `.session_id`; read last `assistant_turn` ts
  from the session log.
- **Cache-miss indicator (#3).** From the last `assistant_turn` `delta_by_type`:
  flag ❄ when `cache_create > 0.5 × cache_read` (the COLD-turn signature).
- **Large-context indicator (#3).** `context_window.used_percentage` is already in
  statusline stdin (drives the bar). Add a marker when large to hint "big context =
  every turn is expensive → consider a fresh session."

Behavioral (CLAUDE.md — PENDING, location undecided, see open questions):
- **Propose starting a new session at sensible points (#6a)** — when context grows
  large / topic switches (large context = per-turn cost multiplier).
- **Evaluate Opus necessity & propose downgrade (#7)** — assess whether the
  task/topic needs Opus; propose Sonnet when it doesn't.
- **Route subagents to Sonnet** — audit agent types; pin Explore / search / review
  agents to Sonnet (they inherit Opus today).
- **Reduce long mid-task idles** — 26% of prompts trigger a re-cache; batching
  questions / staying engaged during a task avoids TTL expiry.

## 3. Tracking & analysis improvements (+ potential)

**Log gaps found:**
| gap | status |
|---|---|
| No `model` field | ✅ FIXED — added to `assistant_turn` (from transcript, last non-sidechain msg) |
| Skill/Agent name never captured (Skill + Agent calls opaque) | ✅ FIXED — `label` on `tool_start` = `.skill` / `.subagent_type` |
| No per-tool cost | ✅ FIXED — `cost_at_start`/`cost_at_end`/`cost_delta_tool` on tool events (coarse: only meaningful for slow tools) |
| No session metadata (cwd/branch/project) | ✅ FIXED — new `session_start` event + `SessionStart` hook |
| `cost_per_token` null ~27% | structural (cost fires before first turn writes token state) — low priority |
| `desc` missing on 21% of tool_starts | ✅ partly — added `.description` fallback + `label` |
| Subagent-vs-main split invisible in session-logs | recoverable from transcripts via `isSidechain` / `/subagents/` path |
| Cost logging starts 06-23 (transcripts to 06-03) | historical, N/A |
| 1 malformed timestamp | trivial |

**Metrics worth tracking going forward:**
1. $/day and **$/experiment** — via `session_start` (branch/project) + edited-file
   path-prefix at query time (generalizes the repo-specific `experiments/<name>/`).
2. Cache-efficiency ratio (cache_read ÷ cache_create) per session.
3. Idle-expiry count (>5-min gaps) as a behavioral metric.
4. Model mix per day (catch silent routing changes).
5. Alert when a session's blended rate > 5 $/M (reliable cache-miss detector).
6. Skill/agent leaderboard (now that `label` is captured).

**Potential (bigger):** cross-session aggregator reading the new fields (spend by
model / skill / branch / experiment-subtree); a `report`-mode rollup across sessions.

---

## Work already DONE this session (2026-07-06)

Live changes (already active for the current session's turns):
- `~/.claude/session-logger.sh`:
  - `assistant_turn` now carries `model`.
  - `tool_start` now carries `label` (skill / subagent_type) + `cost_at_start`;
    `desc` gained `.description` fallback.
  - `tool_end` now carries `cost_at_end` + `cost_delta_tool`.
  - new `session_start` mode → logs `cwd`, `git_root`, `git_branch`, `project`,
    `source`.
- `~/.claude/settings.json`: added `SessionStart` hook (loads next launch).
- Notes on the session logger updated with the new schema.
- All smoke-tested; `bash -n` + `jq empty` clean.

## PENDING → DONE (completed 2026-07-06, session after `<session-B>`)

- [x] #1 Idle timer in status line — `statusline.sh`: 💤 `now − last assistant_turn ts`,
      dim <3m / amber 3–5m / **red ≥5m** (cache cooling). Reads log via `tac | grep -m1`.
- [x] #3 Status-line nudges — **❄** cold-turn flag (last turn `cache_create > ½ cache_read`)
      next to context %; **↻new?** dim hint at context ≥70%.
- [x] #4 Skill `~/.claude/skills/spend-analysis/` — `SKILL.md` playbook + all 8 analysis
      scripts under `scripts/`; smoke-run clean; skill is registered/discoverable.
- [x] #6a/#7 → **separate global doc** `~/.claude/cost-awareness.md** (per user: keep it
      standalone so it bundles into the distribution zip), referenced from a new
      `~/.claude/CLAUDE.md`. Assertiveness set to **every session / topic start** (per
      user; noted in-file as easy to dial back to threshold-triggered). Covers: model-fit
      (propose Sonnet), session-freshness (propose fresh session), **offload large reads
      to a subagent** (new nudge, user-suggested), route read-only subagents to Sonnet,
      avoid >5-min idle.
- [x] #6b `tmp/session-logger.zip` rebuilt — live `session-logger.sh` (new schema),
      `statusline.sh` (with signals), `statusline-cost-tap.sh`, `cost-awareness.md`,
      `hooks-snippet.json` (now includes **SessionStart**), agent-runnable README. 7 files;
      JSON + `bash -n` validated.
- [x] Subagent audit — **outcome: no mass edit.** All nWave `*-reviewer` agents already
      pin Haiku; nWave primary agents use `model: inherit` **by design** (reasoning roles;
      vendored `~/.claude/agents/nw/` — owner's call, quality risk to downgrade). Built-in
      `Explore`/`general-purpose`/`Plan` + superpowers subagents have **no def files** and
      can't be frontmatter-pinned → the safe lever is **dispatch-time `model: sonnet`** for
      read-only subagents, now codified in `cost-awareness.md`.

## REFINEMENTS (post-review, same session)

- **Idle timer rebased** onto last *activity* (user_prompt | assistant_turn | tool_end —
  all reset the cache TTL; `cost` events excluded to avoid self-reset), not just the last
  answer.
- **`refreshInterval: 10`** added to `settings.json` statusLine — without it the statusline
  only renders on activity, so the idle 💤 froze right after a turn (observed "sits at
  0m1s"). Confirmed against docs: triggers "go quiet when the main session is idle";
  `refreshInterval` re-runs it on a fixed timer for time-based data.
- **CLAUDE.md slimmed to a mandatory-read pointer**; all model-fit / keep-context-lean
  guidance lives only in `cost-awareness.md`, which now carries a `MANDATORY-READ` marker.
- **`spend-analysis` skill added to the distribution zip** (`session-logger/skills/…`), so
  the bundle is a complete kit (logger → skill → cost-awareness). Zip now 19 files.

## OPEN QUESTIONS — RESOLVED (2026-07-06)

1. **Location** → **global, in a separate doc** (`~/.claude/cost-awareness.md`) referenced
   by `~/.claude/CLAUDE.md`, so it can be dropped into the cost-analysis distribution zip.
2. **Assertiveness** → **every session / topic start** (try it, dial back if repetitive;
   the file says how).
