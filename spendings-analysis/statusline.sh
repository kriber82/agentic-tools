#!/bin/bash
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name')
DIR=$(echo "$input"   | jq -r '.workspace.current_dir')
PCT=$(echo "$input"   | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
COST=$(echo "$input"  | jq -r '.cost.total_cost_usd // 0')

# Session activity log: tap cost snapshots (the statusline stdin is where cost is
# reliably exposed). Fire-and-forget; never let logging break the status line.
[ -x "$HOME/.claude/statusline-cost-tap.sh" ] && \
    printf '%s' "$input" | "$HOME/.claude/statusline-cost-tap.sh" || true

# Colors
CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; DIM='\033[2m'; RESET='\033[0m'

# --- Line 1: model, folder, git ---
FOLDER="${DIR##*/}"
GIT_PART=""
if git -C "$DIR" rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
    STAGED=$(git -C "$DIR" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    MODIFIED=$(git -C "$DIR" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    GIT_PART=" | 🌿 $BRANCH"
    [ "$STAGED" -gt 0 ]   && GIT_PART="$GIT_PART ${GREEN}+${STAGED}${RESET}"
    [ "$MODIFIED" -gt 0 ] && GIT_PART="$GIT_PART ${YELLOW}~${MODIFIED}${RESET}"
fi
echo -e "${CYAN}[${MODEL}]${RESET} 📁 ${FOLDER}${GIT_PART}"

# --- Line 2: context bar, session cost ---
PCT_INT=${PCT:-0}
if   [ "$PCT_INT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT_INT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else                              BAR_COLOR="$GREEN"
fi

FILLED=$((PCT_INT / 10))
EMPTY=$((10 - FILLED))
BAR=""
[ "$FILLED" -gt 0 ] && printf -v F "%${FILLED}s" && BAR="${F// /▓}"
[ "$EMPTY"  -gt 0 ] && printf -v E "%${EMPTY}s"  && BAR="${BAR}${E// /░}"

COST_FMT=$(printf '$%.3f' "$COST")

# --- Session-log signals (↻new? + ❄ next to context %, 💤 idle at the end) ---
# All the signal logic lives in statusline-signals.sh so it can be reused in your
# own statusline; here we just ask for the two placements. (Needs "refreshInterval"
# on statusLine in settings.json for the 💤 timer to advance while you're idle.)
SIG_CTX=""; SIG_IDLE=""
if [ -x "$HOME/.claude/statusline-signals.sh" ]; then
    SIG_CTX=$(printf '%s' "$input"  | "$HOME/.claude/statusline-signals.sh" context)
    SIG_IDLE=$(printf '%s' "$input" | "$HOME/.claude/statusline-signals.sh" idle)
fi

echo -e "${BAR_COLOR}${BAR}${RESET} ${PCT_INT}%${SIG_CTX} | ${DIM}session${RESET} ${YELLOW}${COST_FMT}${RESET}${SIG_IDLE}"
