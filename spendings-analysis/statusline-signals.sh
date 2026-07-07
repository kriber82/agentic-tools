#!/bin/bash
# Statusline signal fragments for the spend-analysis kit. Reads the Claude Code
# statusLine JSON on stdin and prints ready-to-render ANSI fragments to stdout:
#   💤 idle timer, ❄ cold-turn flag, ↻new? large-context hint.
#
# Modes (first arg):
#   all (default) -> ↻new? ❄ then 💤, as one fragment to append at the end of your line
#   context       -> ↻new? large-context hint + ❄ cold-turn flag (put right after your context %)
#   idle          -> 💤 idle timer (put at the end of your line)
#
# Drop-in for your OWN statusline: capture stdin once, then pipe it here. Example:
#   input=$(cat)
#   CTX=$(printf '%s' "$input" | "$HOME/.claude/statusline-signals.sh" context)
#   IDLE=$(printf '%s' "$input" | "$HOME/.claude/statusline-signals.sh" idle)
#   echo -e "…bar ${PCT}%${CTX}… | 💲${COST}${IDLE}"
#
# Output is real ANSI (so plain echo/printf render it too). Requires jq; prints
# nothing and exits 0 if jq is missing or data is unavailable, so it can never
# break your status line.
#
# NOTE: the 💤 idle timer only advances live while you're away if settings.json
# sets "refreshInterval" on statusLine — otherwise the statusline redraws only on
# activity and the timer appears frozen.
#
# DEPENDENCIES: 💤 and ❄ need `tac` and GNU `date -d` (coreutils) — i.e. a Linux
# environment or devcontainer. On stock macOS/BSD (no coreutils) those two silently
# render nothing; ↻new? works everywhere. jq is required for all three.
set -u

mode="${1:-all}"
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
SID=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
PCT=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0' 2>/dev/null | cut -d. -f1)
PCT=${PCT:-0}

DIM='\033[2m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'

IDLE_PART=""; COLD_PART=""; CTX_HINT=""

# ↻new? large-context hint (context ≥70%): big context ⇒ every turn re-reads it.
if [ "$mode" != "idle" ]; then
    [ "$PCT" -ge 70 ] 2>/dev/null && CTX_HINT=" ${DIM}↻new?${RESET}"
fi

LOG="$HOME/.claude/session-logs/$SID.jsonl"
if [ -n "$SID" ] && [ -f "$LOG" ]; then
    # 💤 idle = now − last real activity. A prompt, an answer, OR a tool result all
    # hit the API and refresh the cache TTL, so any of them counts. 'cost' events
    # are excluded (a statusline may emit them itself → would self-reset to ~0).
    # tac = read the log from the end (cheap even on large logs).
    if [ "$mode" = "all" ] || [ "$mode" = "idle" ]; then
        LAST_TS=$(tac "$LOG" 2>/dev/null \
            | grep -m1 -E '"event":"(user_prompt|assistant_turn|tool_end)"' \
            | jq -r '.ts // empty' 2>/dev/null)
        LAST_EPOCH=$(date -d "$LAST_TS" +%s 2>/dev/null || echo 0)
        if [ "${LAST_EPOCH:-0}" -gt 0 ]; then
            IDLE_S=$(( $(date +%s) - LAST_EPOCH ))
            [ "$IDLE_S" -lt 0 ] && IDLE_S=0
            # ≥5min = ephemeral cache TTL lapsed (red = cooling warning); 3–5min amber.
            if   [ "$IDLE_S" -ge 300 ]; then IDLE_COLOR="$RED"
            elif [ "$IDLE_S" -ge 180 ]; then IDLE_COLOR="$YELLOW"
            else                              IDLE_COLOR="$DIM"
            fi
            IDLE_PART=" | ${IDLE_COLOR}💤$(( IDLE_S / 60 ))m$(( IDLE_S % 60 ))s${RESET}"
        fi
    fi
    # ❄ cold-turn: last assistant_turn's cache_create > ½ cache_read (a re-cache).
    if [ "$mode" = "all" ] || [ "$mode" = "context" ]; then
        LAST_TURN=$(tac "$LOG" 2>/dev/null | grep -m1 '"event":"assistant_turn"')
        if [ -n "$LAST_TURN" ]; then
            CR=$(printf '%s' "$LAST_TURN" | jq -r '.delta_by_type.cache_read // 0' 2>/dev/null)
            CC=$(printf '%s' "$LAST_TURN" | jq -r '.delta_by_type.cache_create // 0' 2>/dev/null)
            awk -v cc="$CC" -v cr="$CR" 'BEGIN{exit !(cc>0 && cc>0.5*cr)}' \
                && COLD_PART=" ${RED}❄${RESET}"
        fi
    fi
fi

case "$mode" in
    idle)    OUT="$IDLE_PART" ;;
    context) OUT="${CTX_HINT}${COLD_PART}" ;;
    *)       OUT="${CTX_HINT}${COLD_PART}${IDLE_PART}" ;;
esac
printf '%b' "$OUT"
