#!/bin/bash
# Cost tap for the per-session activity logger.
#
# Claude Code feeds the statusLine command a JSON blob on stdin that includes
# session id, cumulative cost, and duration. This is where cost is reliably
# exposed (the transcript's costUSD may be null). This script
# reads that JSON and forwards a cost snapshot to session-logger.sh.
#
# Drop-in for your OWN statusline: capture stdin once into a variable, then add
# one line that pipes it here. Example:
#
#     input=$(cat)
#     # ... your existing statusline rendering using "$input" ...
#     printf '%s' "$input" | "$HOME/.claude/statusline-cost-tap.sh"
#
# This script extracts the fields it needs itself, so it does not care what your
# statusline names its variables. It writes nothing to stdout and always exits 0,
# so it can never break or slow your status line in a visible way.

input=$(cat)

# jq is required; if it's missing just no-op rather than erroring the caller.
command -v jq >/dev/null 2>&1 || exit 0

SID=$(printf '%s' "$input"  | jq -r '.session_id // empty'           2>/dev/null)
COST=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // 0'      2>/dev/null)
DUR=$(printf '%s' "$input"  | jq -r '.cost.total_duration_ms // 0'   2>/dev/null)

[ -n "$SID" ] && [ -x "$HOME/.claude/session-logger.sh" ] && \
    "$HOME/.claude/session-logger.sh" cost "$SID" "$COST" "$DUR" >/dev/null 2>&1

exit 0
