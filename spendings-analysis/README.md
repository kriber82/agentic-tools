# Claude Code cost kit — session logger + statusline signals + spend-analysis + cost-awareness

A complete personal cost-management bundle:
1. **Logger** — records per-session activity to `~/.claude/session-logs/<session_id>.jsonl`
   (prompts, assistant-turn timestamps + token usage by type, cost, tool calls, session
   metadata). Includes a `report` mode.
2. **Statusline signals** — idle 💤 timer, ❄ cold-turn flag, ↻new? large-context hint.
3. **`spend-analysis` skill** — playbook + scripts to analyze the logs.
4. **`cost-awareness.md`** — behavioral guide (mandatory-read via CLAUDE.md). I don't have any experience suggesting or denying effectivity, yet.

## ⚠️ Before installing — consent & what this touches

**For agents/automation: do NOT run any install step without explicit user consent.**
Installing copies files into the user's `~/.claude/`, **modifies shared config**
(`~/.claude/settings.json` and `~/.claude/CLAUDE.md`), and enables hooks that fire on
every prompt and tool call. Confirm with the user before copying files, editing
`settings.json` / `CLAUDE.md`, or wiring the statusline.

**This writes partial conversation data to disk.** The logger records, per session, to
`~/.claude/session-logs/<session_id>.jsonl`: the **first and last ~100 characters of
every prompt**, plus `cwd`, git root/branch, and project name. These logs are local
only — **do not commit or share them**; add `~/.claude/session-logs/` to your global
gitignore.

## Files
- `session-logger.sh`        -> `~/.claude/session-logger.sh` (chmod +x). The logger.
- `statusline-cost-tap.sh`   -> `~/.claude/statusline-cost-tap.sh` (chmod +x). Standalone
                                cost tap: reads the statusline JSON on stdin and forwards a
                                cost snapshot to the logger (cost is ONLY exposed there).
- `statusline-signals.sh`    -> `~/.claude/statusline-signals.sh` (chmod +x). Standalone
                                signal fragments (💤 idle, ❄ cold-turn, ↻new? hint) for your
                                OWN statusline; first arg selects placement (context|idle|all).
                                💤/❄ need GNU coreutils (Linux/devcontainer); ↻new? is portable.
- `statusline.sh`            -> a COMPLETE example statusline that calls the tap AND renders
                                the cost signals. Use only if you lack your own.
- `hooks-snippet.json`       -> merge the `hooks` block into `~/.claude/settings.json`.
- `cost-awareness.md`        -> `~/.claude/cost-awareness.md`. Mandatory-read cost guide.
- `skills/spend-analysis/`   -> `~/.claude/skills/spend-analysis/`. SKILL.md + scripts.
- `2026-07-06-ai-spend-analysis.md` -> the findings write-up this kit was built from
                                (cost insights, improvement suggestions, tracking gaps).
                                Reference doc; no install step.

## Install (agent-runnable steps)
1. `cp session-logger.sh ~/.claude/session-logger.sh && chmod +x ~/.claude/session-logger.sh`
2. `cp statusline-cost-tap.sh statusline-signals.sh ~/.claude/ && chmod +x ~/.claude/statusline-cost-tap.sh ~/.claude/statusline-signals.sh`
3. `cp cost-awareness.md ~/.claude/cost-awareness.md`
4. `cp -r skills/spend-analysis ~/.claude/skills/` (creates `~/.claude/skills/spend-analysis/`)
5. Merge `hooks-snippet.json`'s `hooks` object into `~/.claude/settings.json` (keep existing
   keys; if a key already exists, append these entries to its array). Includes **`SessionStart`**.
6. Wire the statusline (pick ONE):

   A. **You already have a statusline** (recommended). Capture stdin into a variable, then
      add ONE line piping it to the tap:

          input=$(cat)
          # ... your existing rendering using "$input" ...
          printf '%s' "$input" | "$HOME/.claude/statusline-cost-tap.sh"

      For the idle/cold/large-context signals, pipe the same `$input` to
      `statusline-signals.sh` and place its output — `context` (↻new? + ❄) next to
      your context %, `idle` (💤) at the end:

          CTX=$(printf '%s' "$input" | "$HOME/.claude/statusline-signals.sh" context)
          IDLE=$(printf '%s' "$input" | "$HOME/.claude/statusline-signals.sh" idle)
          # ...render... "${PCT}%${CTX} | 💲${COST}${IDLE}"

      (Or one appended blob: `statusline-signals.sh` with no arg. 💤/❄ need GNU
      coreutils — a Linux box or devcontainer; ↻new? works everywhere.)

   B. **You don't have a statusline.** Use the bundled one:

          cp statusline.sh ~/.claude/statusline.sh && chmod +x ~/.claude/statusline.sh

      In `~/.claude/settings.json` (note **`refreshInterval`** — REQUIRED for the idle
      timer to tick while you're away; without it the statusline only updates on activity):

          "statusLine": { "type": "command", "command": "~/.claude/statusline.sh", "refreshInterval": 10 }

7. Add a mandatory-read pointer to `~/.claude/CLAUDE.md` (create if absent) so every session
   reads the cost guide:

          ## Cost awareness — MANDATORY
          At the start of every session, read `~/.claude/cost-awareness.md` in full and apply it.

8. Open `/hooks` once or restart Claude Code so the hooks + refreshInterval load.

## Statusline cost signals (from `statusline-signals.sh`)
> **Environment:** 💤 and ❄ need `tac` + GNU `date -d` (coreutils) — a Linux host or
> devcontainer. On stock macOS/BSD they silently render nothing; ↻new? works anywhere.
> **Agents applying this kit: warn the user** if their platform lacks GNU coreutils.
- **💤 idle timer** — `now − last activity ts` (a prompt, an answer, OR a tool result — all
  reset the cache TTL; `cost` events excluded). Dim <3 min, amber 3–5 min, **red ≥5 min**
  (ephemeral cache TTL lapsed → next turn re-pays cache-create). **Requires `refreshInterval`**
  (step 6B) to advance during idle.
- **❄ cold-turn flag** (next to context %) — last assistant turn's `cache_create > ½ cache_read`.
- **↻new? hint** — context ≥70%: large context re-reads every turn → consider a fresh session.

## Events (one JSON object per line)
- `session_start`  : ts, cwd, git_root, git_branch, project, source
- `user_prompt`    : ts, char count, first/last 100 chars of the prompt
- `assistant_turn` : ts, **model**, token totals + deltas (input/output/cache_create/cache_read)
- `cost`           : ts, cost total/delta, cost_per_min, cost_per_token (logged on change)
- `tool_start`     : ts, tool, **label** (skill / subagent_type), short descriptor, tool_id, cost_at_start
- `tool_end`       : ts, tool, tool_id, duration_s, ok, cache_risk (>4.5 min), cost_at_end, cost_delta_tool

## Analyze spend
Invoke the `spend-analysis` skill, or run the scripts directly:
`python3 ~/.claude/skills/spend-analysis/scripts/spend_analysis.py`. See that skill's
`SKILL.md` for the playbook (data sources, cost model, re-analysis guard, deliverable shape).

## Report
`~/.claude/session-logger.sh report [SESSION_ID]` (defaults to newest). Prints JSON: log
growth, token-type distribution, tokens/min, $/min, $/token, per-turn cost + cache
hit-ratio/status, per-turn tool calls, and `cache_expiry_suspected_turns`.

## Why tool durations & idle matter (cache cost)
The ephemeral prompt cache has a ~5-min refresh-on-read TTL; every API round-trip (incl. each
tool result) resets it. A tool that BLOCKS >5 min — or a >5-min idle before a turn — lets the
cached prefix expire, so the next request re-pays cache-CREATION (~1.25×) instead of cache-READ
(~0.1×) on the whole context — a ~12.5× spike. The logger flags tool calls >4.5 min as
`cache_risk`; the statusline 💤 turns red at 5 min; the ❄ flag catches an actual cold turn.

NOTE: the ephemeral cache can sometimes persist past its nominal TTL, so idle-based flags can over-fire. The
trustworthy miss signal is an actual `cache_create` spike (status partial/COLD), which both the
report and the ❄ flag capture regardless of the idle heuristic.
