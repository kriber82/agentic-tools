#!/bin/bash
# Per-session activity logger for Claude Code.
# Writes one JSONL event per line to ~/.claude/session-logs/<session_id>.jsonl
#
# Modes:
#   prompt    < hook stdin (UserPromptSubmit)            — logs user message (ts + first/last ~100 chars)
#   stop      < hook stdin (Stop)                        — logs assistant turn end (ts) + token deltas
#   cost SID COST DURMS                                   — called from statusline.sh on cost snapshots
#   tool_start< hook stdin (PreToolUse)                   — logs a tool call starting (ts, name, descriptor)
#   tool_end  < hook stdin (PostToolUse/PostToolUseFailure)— logs a tool call ending (ts, duration, cache_risk)
#   report [SID]                                          — prints a per-turn analysis (see below)
#
# Cost (#3/#5) is not reliably exposed in the transcript, so it is
# tapped from the statusline's stdin instead. Token deltas (#4) come from the
# transcript usage fields. Each side persists its latest cumulative value to a
# state file so the other can attach cost-per-token (#5).
#
# Tool calls matter for cost because the ephemeral prompt cache has a 5-min
# refresh-on-read TTL: each API round-trip (incl. each tool result) resets it.
# A single tool call that blocks > 5 min lets the cached prefix expire, so the
# next request re-pays cache-CREATION (~1.25x) instead of cache-READ (~0.1x) on
# the whole context — a ~12.5x cost spike. tool_end flags cache_risk at > 4.5min.

set -euo pipefail

LOG_DIR="$HOME/.claude/session-logs"
STATE_DIR="$LOG_DIR/.state"
mkdir -p "$STATE_DIR"

mode="${1:-}"

# ts with millisecond precision, UTC
now() { date -u +%Y-%m-%dT%H:%M:%S.%3NZ; }

logfile() { echo "$LOG_DIR/$1.jsonl"; }

case "$mode" in
  prompt)
    input=$(cat)
    sid=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
    prompt=$(printf '%s' "$input" | jq -r '.prompt // ""')
    len=${#prompt}
    if [ "$len" -le 210 ]; then
      head_s=$prompt; tail_s=""
    else
      head_s=${prompt:0:100}; tail_s=${prompt: -100}
    fi
    jq -nc --arg ts "$(now)" --arg head "$head_s" --arg tail "$tail_s" \
      --argjson len "$len" \
      '{ts:$ts, event:"user_prompt", chars:$len, text_head:$head, text_tail:$tail}' \
      >> "$(logfile "$sid")"
    ;;

  stop)
    input=$(cat)
    sid=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
    tpath=$(printf '%s' "$input" | jq -r '.transcript_path // ""')

    # Model of the last (main-loop) assistant message — closes the "no model
    # logged" gap; recoverable per turn straight from the transcript. (#1)
    model=""
    if [ -n "$tpath" ] && [ -f "$tpath" ]; then
      model=$(jq -rs '[ .[] | select(.type=="assistant" and (.isSidechain != true)) | .message.model ] | last // ""' "$tpath" 2>/dev/null || echo "")
    fi

    # Cumulative token totals across all assistant messages in the transcript.
    if [ -n "$tpath" ] && [ -f "$tpath" ]; then
      totals=$(jq -s '
        [ .[] | select(.type=="assistant") | .message.usage ]
        | { input:        (map(.input_tokens // 0)                | add // 0),
            output:       (map(.output_tokens // 0)               | add // 0),
            cache_create: (map(.cache_creation_input_tokens // 0) | add // 0),
            cache_read:   (map(.cache_read_input_tokens // 0)     | add // 0) }
        | . + { total: (.input + .output + .cache_create + .cache_read) }' "$tpath")
    else
      totals='{"input":0,"output":0,"cache_create":0,"cache_read":0,"total":0}'
    fi

    statef="$STATE_DIR/$sid.tokens"
    prev='{"input":0,"output":0,"cache_create":0,"cache_read":0,"total":0}'
    [ -f "$statef" ] && prev=$(cat "$statef")

    # Latest known cumulative cost (from statusline), for cost-per-token.
    cost_total=$(cat "$STATE_DIR/$sid.cost" 2>/dev/null || echo "")

    jq -nc --arg ts "$(now)" --arg model "$model" \
      --argjson cur "$totals" --argjson prev "$prev" \
      --arg cost "$cost_total" '
      ($cur.total - $prev.total) as $dtot
      | { ts:$ts, event:"assistant_turn",
          tokens_total: $cur.total,
          tokens_delta: $dtot,
          delta_by_type: {
            input:        ($cur.input        - $prev.input),
            output:       ($cur.output       - $prev.output),
            cache_create: ($cur.cache_create - $prev.cache_create),
            cache_read:   ($cur.cache_read   - $prev.cache_read) },
          cumulative_by_type: $cur }
      | if ($model|length)>0 then . + {model:$model} else . end
      | if ($cost|length)>0 and $cur.total>0
        then . + { cost_per_token: (($cost|tonumber) / $cur.total) }
        else . end' \
      >> "$(logfile "$sid")"

    printf '%s' "$totals" > "$statef"
    ;;

  cost)
    sid="${2:-unknown}"
    cost="${3:-0}"
    durms="${4:-0}"
    [ "$sid" = "unknown" ] && exit 0

    statef="$STATE_DIR/$sid.cost"
    prev=$(cat "$statef" 2>/dev/null || echo "")

    # Only log when the cumulative cost actually changes.
    [ "$cost" = "$prev" ] && exit 0

    tokens_total=$(jq -r '.total // empty' "$STATE_DIR/$sid.tokens" 2>/dev/null || echo "")

    jq -nc --arg ts "$(now)" --arg cost "$cost" --arg prev "$prev" \
      --arg durms "$durms" --arg tok "$tokens_total" '
      ($cost|tonumber) as $c
      | (if ($prev|length)>0 then ($prev|tonumber) else 0 end) as $p
      | (($durms|tonumber)/60000) as $mins
      | { ts:$ts, event:"cost",
          cost_total: $c,
          cost_delta: ($c - $p),
          duration_min: $mins,
          cost_per_min: (if $mins>0 then ($c/$mins) else 0 end) }
      | if ($tok|length)>0 and ($tok|tonumber)>0
        then . + { tokens_total:($tok|tonumber), cost_per_token: ($c/($tok|tonumber)) }
        else . end' \
      >> "$(logfile "$sid")"

    printf '%s' "$cost" > "$statef"
    ;;

  tool_start)
    input=$(cat)
    sid=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
    tool=$(printf '%s' "$input" | jq -r '.tool_name // "unknown"')

    # Short (<=50 char) human descriptor: bash command, or file path, else "".
    desc=$(printf '%s' "$input" | jq -r '
      .tool_input as $i
      | ($i.command // $i.file_path // $i.path // $i.pattern // $i.description // "")
      | tostring' 2>/dev/null || echo "")
    desc=$(printf '%s' "$desc" | tr "\n" " ")
    [ "${#desc}" -gt 50 ] && desc="${desc:0:50}"

    # Semantic name for tools whose "identity" isn't a command/path: the invoked
    # skill (Skill.skill) or the dispatched subagent type (Agent/Task.subagent_type).
    # Lets cost be grouped by which skill/agent ran, not just "Skill"/"Agent". (#2)
    label=$(printf '%s' "$input" | jq -r '
      .tool_input as $i | ($i.skill // $i.subagent_type // "") | tostring' 2>/dev/null || echo "")

    # Correlate start<->end: hash tool name + raw input. A given (tool,input) maps
    # to one in-flight call; the matching tool_end clears the timer file.
    raw=$(printf '%s' "$input" | jq -c '{tool_name, tool_input}' 2>/dev/null || echo "$tool")
    tid=$(printf '%s' "$raw" | cksum | cut -d' ' -f1)

    # Cumulative cost at the moment this tool starts (from the statusline state
    # file). Paired with the reading in tool_end to bracket the tool's own spend. (#4)
    cost_start=$(cat "$STATE_DIR/$sid.cost" 2>/dev/null || echo "")

    # Record start epoch (ms) + cost-at-start on one line for tool_end to consume.
    printf '%s %s\n' "$(date +%s.%3N)" "${cost_start:-}" > "$STATE_DIR/$sid.tool.$tid"

    jq -nc --arg ts "$(now)" --arg tool "$tool" --arg desc "$desc" \
      --arg label "$label" --arg tid "$tid" --arg cost "${cost_start:-}" '
      { ts:$ts, event:"tool_start", tool:$tool, tool_id:$tid }
      | if ($label|length)>0 then . + {label:$label} else . end
      | if ($desc|length)>0  then . + {desc:$desc}   else . end
      | if ($cost|length)>0  then . + {cost_at_start:($cost|tonumber)} else . end' \
      >> "$(logfile "$sid")"
    ;;

  tool_end)
    input=$(cat)
    sid=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
    tool=$(printf '%s' "$input" | jq -r '.tool_name // "unknown"')
    # PostToolUseFailure sets this; PostToolUse leaves it absent -> ok=true.
    ok=$(printf '%s' "$input" | jq -r 'if .hook_event_name == "PostToolUseFailure" then "false" else "true" end' 2>/dev/null || echo "true")

    raw=$(printf '%s' "$input" | jq -c '{tool_name, tool_input}' 2>/dev/null || echo "$tool")
    tid=$(printf '%s' "$raw" | cksum | cut -d' ' -f1)

    tf="$STATE_DIR/$sid.tool.$tid"
    dur="null"; cost_start=""
    if [ -f "$tf" ]; then
      read -r start cost_start < "$tf" || true; rm -f "$tf"
      dur=$(awk -v s="$start" -v e="$(date +%s.%3N)" 'BEGIN{ printf "%.3f", e-s }')
    fi
    # Cumulative cost now; delta vs cost-at-start = spend bracketed by this tool. (#4)
    cost_end=$(cat "$STATE_DIR/$sid.cost" 2>/dev/null || echo "")

    jq -nc --arg ts "$(now)" --arg tool "$tool" --arg tid "$tid" \
      --arg dur "$dur" --argjson ok "$ok" \
      --arg cs "${cost_start:-}" --arg ce "${cost_end:-}" '
      { ts:$ts, event:"tool_end", tool:$tool, tool_id:$tid, ok:$ok }
      | if $dur != "null"
        then . + { duration_s: ($dur|tonumber),
                   cache_risk: (($dur|tonumber) > 270) }
        else . end
      | if ($ce|length)>0 then . + {cost_at_end:($ce|tonumber)} else . end
      | if ($cs|length)>0 and ($ce|length)>0
        then . + {cost_delta_tool: (($ce|tonumber) - ($cs|tonumber))} else . end' \
      >> "$(logfile "$sid")"
    ;;

  session_start)
    # Generalized per-workstream attribution (#5): tag the session with the
    # git repo + branch + cwd. "Experiment"/feature is derived at query time from
    # the branch and from the path-prefix of files edited during the session
    # (tool_start already logs file_path) — no repo-specific logic lives here.
    input=$(cat)
    sid=$(printf '%s' "$input" | jq -r '.session_id // "unknown"')
    cwd=$(printf '%s' "$input" | jq -r '.cwd // ""')
    [ -z "$cwd" ] && cwd="$PWD"
    git_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "")
    branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    project=$([ -n "$git_root" ] && basename "$git_root" || echo "")
    src=$(printf '%s' "$input" | jq -r '.source // ""')

    jq -nc --arg ts "$(now)" --arg cwd "$cwd" --arg root "$git_root" \
      --arg branch "$branch" --arg project "$project" --arg src "$src" '
      { ts:$ts, event:"session_start", cwd:$cwd, git_root:$root,
        git_branch:$branch, project:$project }
      | if ($src|length)>0 then . + {source:$src} else . end' \
      >> "$(logfile "$sid")"
    ;;

  report)
    # Summarize a session log: token-type distribution, tokens/min, $/min, $/token.
    # Usage: session-logger.sh report [SESSION_ID]   (defaults to newest log file)
    sid="${2:-}"
    if [ -z "$sid" ]; then
      newest=$(ls -t "$LOG_DIR"/*.jsonl 2>/dev/null | head -1 || true)
      [ -z "$newest" ] && { echo "no session logs found" >&2; exit 1; }
      sid=$(basename "$newest" .jsonl)
    fi
    log="$(logfile "$sid")"
    [ -f "$log" ] || { echo "no log for session $sid" >&2; exit 1; }

    # Log-size metrics (jq cannot stat files) — pass in as args.
    log_bytes=$(wc -c < "$log" | tr -d ' ')
    log_lines=$(wc -l < "$log" | tr -d ' ')

    jq -s --arg sid "$sid" \
      --argjson log_bytes "$log_bytes" --argjson log_lines "$log_lines" '
      def epoch: (sub("\\.[0-9]+Z$";"Z") | fromdateiso8601);
      def r2: (.*100|round/100);
      def r4: (.*10000|round/10000);

      . as $ev
      | [ $ev[] | select(.event=="assistant_turn") ] as $turns
      | [ $ev[] | select(.event=="cost") ]           as $costs
      | [ $ev[] | select(.event=="user_prompt") ]    as $prompts
      | ($costs[-1]) as $lastcost
      | [ $ev[] | select(.event=="cost" and .tokens_total!=null) ] as $tcost

      # ---- tool calls: join each tool_end to its matching tool_start ----
      # (same tool_id, latest start at/before the end). Yields one record per
      # completed call with start/end epoch, duration, descriptor, ok flag.
      | [ $ev[] | select(.event=="tool_start") ] as $tstarts
      | [ $ev[] | select(.event=="tool_end") ]   as $tends
      | [ $tends[]
          | . as $e
          | ([ $tstarts[] | select(.tool_id==$e.tool_id and (.ts|epoch) <= ($e.ts|epoch)) ] | last) as $s
          | { tool: $e.tool,
              start: (if $s then ($s.ts|epoch) else ($e.ts|epoch) end),
              end:   ($e.ts|epoch),
              dur:   ($e.duration_s // null),
              desc:  ($s.desc // null),
              ok:    $e.ok,
              cache_risk: ($e.cache_risk // false) } ] as $tools

      # ---- per-turn records: join prompt -> turn -> cost by timestamp ----
      | [ range(0; ($turns|length)) as $i
          | $turns[$i]                                          as $t
          | ($t.ts|epoch)                                       as $tt
          | (if $i>0 then ($turns[$i-1].ts|epoch) else null end) as $ptt
          # last user_prompt at/just before this turn = start of the wait window
          | ([ $prompts[] | select((.ts|epoch) <= $tt) ] | last) as $pr
          | (if $pr then ($pr.ts|epoch) else null end)         as $prt
          # cost reading that closes the turn / opens the wait window
          | ([ $costs[] | select((.ts|epoch) >= $tt) ] | first) as $cend
          | ([ $costs[] | select((.ts|epoch) <= ($prt // $tt)) ] | last) as $cstart
          | ($t.delta_by_type)                                 as $d
          | (($d.cache_read // 0) + ($d.cache_create // 0) + ($d.input // 0)) as $ctx
          | (if $prt and ($tt > $prt) then (($tt-$prt)/60) else null end) as $wait_min
          | (if $cend and $cstart then ($cend.cost_total - $cstart.cost_total) else null end) as $tcost_usd
          # tool calls belonging to this turn: end ts within (prev turn end, this turn end]
          | [ $tools[] | select(.end <= $tt and (($ptt == null) or (.end > $ptt))) ] as $tt_tools
          | ([ $tt_tools[] | .dur | select(. != null)] ) as $durs
          # true between-turn idle = this turn prompt minus previous turn end
          # (the think/type gap). This is the interval that governs cache TTL,
          # NOT the Stop-to-Stop gap (which wrongly includes this turn runtime).
          | (if $prt and $ptt and ($prt > $ptt) then (($prt-$ptt)/60) else null end) as $idle_min
          | {
              turn: ($i+1),
              ts: $t.ts,
              gap_since_prev_turn_min: (if $ptt then (($tt-$ptt)/60|r2) else null end),

              # ---- Q2: use & pay per turn ----
              per_turn: {
                tokens_total: $t.tokens_delta,
                by_type: $d,
                cost_usd: (if $tcost_usd != null then ($tcost_usd|r4) else null end)
              },

              # ---- tool calls this turn ----
              tools: {
                count: ($tt_tools|length),
                max_duration_s: (if ($durs|length)>0 then ($durs|max|r2) else null end),
                slowest: (
                  ($tt_tools | sort_by(.dur // 0) | last) as $sl
                  | if $sl and ($sl.dur != null)
                    then { tool: $sl.tool, desc: $sl.desc, duration_s: ($sl.dur|r2),
                           cache_risk: $sl.cache_risk }
                    else null end),
                cache_risk_calls: [ $tt_tools[] | select(.cache_risk) | {tool, desc, duration_s: (.dur|r2)} ],
                failures: [ $tt_tools[] | select(.ok==false) | {tool, desc} ]
              },

              # ---- Q1: cache health this turn ----
              cache: {
                read: ($d.cache_read // 0),
                created: ($d.cache_create // 0),
                fresh_input: ($d.input // 0),
                hit_ratio: (if $ctx>0 then (($d.cache_read // 0)/$ctx|r2) else null end),
                status: (
                  if $ctx==0 then "n/a"
                  elif (($d.cache_read // 0)/$ctx) >= 0.7 then "warm"
                  elif (($d.cache_read // 0)/$ctx) >= 0.3 then "partial"
                  else "COLD" end),
                # Attribute a likely TTL expiry to its cause: a >5min think/type
                # idle before the turn, or a single >5min blocking tool within it.
                expiry_suspect: (
                  ([ $tt_tools[] | .dur | select(. != null and . > 300) ] | length > 0) as $slow_tool
                  | ($idle_min != null and $idle_min > 5) as $slow_idle
                  | if $slow_tool then "tool>5min (blocked cache read mid-turn)"
                    elif $slow_idle then "idle \($idle_min|r2)min before turn > 5min TTL"
                    else null end)
              },

              # ---- Q3: use & pay per minute while waiting for the answer ----
              while_waiting: (
                if $wait_min then {
                  wait_min: ($wait_min|r2),
                  output_per_min:  (($d.output // 0)/$wait_min|round),
                  total_per_min:   ($t.tokens_delta/$wait_min|round),
                  cost_per_min_usd:(if $tcost_usd != null then ($tcost_usd/$wait_min|r4) else null end)
                } else null end)
            }
        ] as $perturn

      | {
          session: $sid,
          summary: {
            log_size: {
              bytes: $log_bytes,
              kib: ($log_bytes/1024|r2),
              lines: $log_lines,
              bytes_per_event: (if $log_lines>0 then ($log_bytes/$log_lines|round) else null end),
              tool_events: ([ $ev[] | select(.event=="tool_start" or .event=="tool_end") ] | length),
              kib_per_turn: (if ($turns|length)>0 then ($log_bytes/1024/($turns|length)|r2) else null end)
            },
            turns_logged: ($turns|length),
            session_duration_min: (if $lastcost then ($lastcost.duration_min|r2) else null end),
            cost_total_usd: (if $lastcost then ($lastcost.cost_total|r2) else null end),
            blended_cost_per_token_usd: (if ($tcost|length)>0 then $tcost[-1].cost_per_token else null end),
            tokens_per_usd: (if ($tcost|length)>0 and $tcost[-1].cost_total>0
                             then ($tcost[-1].tokens_total/$tcost[-1].cost_total|round) else null end),
            cumulative_by_type: ($turns[-1].cumulative_by_type // {}),
            distribution_pct: (
              ($turns[-1].cumulative_by_type // {}) as $c
              | if ($c.total // 0)>0 then {
                  input:        (($c.input        / $c.total)*100|r2),
                  output:       (($c.output       / $c.total)*100|r2),
                  cache_create: (($c.cache_create / $c.total)*100|r2),
                  cache_read:   (($c.cache_read   / $c.total)*100|r2)
                } else null end),
            cache_cold_turns: [ $perturn[] | select(.cache.status=="COLD") | .turn ],
            cache_expiry_suspected_turns: [ $perturn[] | select(.cache.expiry_suspect != null) | {turn, cause: .cache.expiry_suspect} ],
            avg_cache_hit_ratio: (
              [ $perturn[] | .cache.hit_ratio | select(.!=null) ] as $h
              | if ($h|length)>0 then (($h|add)/($h|length)|r2) else null end),
            tool_calls_total: ($tools|length),
            tool_cache_risk_calls: [ $tools[] | select(.cache_risk) | {tool, desc, duration_s: (.dur|r2)} ],
            slowest_tool: (
              ($tools | map(select(.dur != null)) | sort_by(.dur) | last) as $sl
              | if $sl then { tool: $sl.tool, desc: $sl.desc, duration_s: ($sl.dur|r2) } else null end)
          },
          turns: $perturn
        }
    ' "$log"
    ;;

  *)
    echo "usage: session-logger.sh {session_start|prompt|stop|cost SID COST DURMS|tool_start|tool_end|report [SID]}" >&2
    exit 1
    ;;
esac
