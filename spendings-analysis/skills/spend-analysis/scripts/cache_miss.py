#!/usr/bin/env python3
"""Cache-miss / idle-expiry analysis from session-logs."""
import json, glob, os
from datetime import datetime
from collections import Counter

LOG = os.path.expanduser("~/.claude/session-logs")
def pts(s):
    try: return datetime.fromisoformat(s.replace("Z","+00:00"))
    except: return None

miss_turns = 0; total_turns = 0
cc_tokens_on_miss = 0
idle_expiries = 0; idle_gaps = []
big_ctx_turns = 0   # turns re-reading >5M cached tokens

for path in glob.glob(os.path.join(LOG, "*.jsonl")):
    recs = [json.loads(l) for l in open(path) if l.strip()]
    prev_turn_end = None
    for r in recs:
        ev = r.get("event")
        if ev == "user_prompt":
            t = pts(r.get("ts"))
            if t and prev_turn_end:
                gap = (t - prev_turn_end).total_seconds()
                if gap > 0:
                    idle_gaps.append(gap)
                    if gap > 300: idle_expiries += 1
        elif ev == "assistant_turn":
            total_turns += 1
            d = r.get("delta_by_type") or {}
            cc = d.get("cache_create", 0); cr = d.get("cache_read", 0)
            if cr > 5_000_000: big_ctx_turns += 1
            # miss signature: cache_create comparable to or exceeding cache_read
            if cc > 0 and cr >= 0 and cc > 0.5 * max(cr, 1):
                miss_turns += 1; cc_tokens_on_miss += cc
            prev_turn_end = pts(r.get("ts"))

idle_gaps.sort()
n = len(idle_gaps)
def pct(p): return idle_gaps[int(p*n)] if n else 0
print("### IDLE-GAP CACHE EXPIRY (gap = user_prompt_ts - prev_turn_end)")
print(f"  prompts following a turn: {n}")
print(f"  idle gaps > 5min (prefix TTL lapses -> next turn re-pays cache-create): {idle_expiries} ({100*idle_expiries/max(n,1):.0f}%)")
print(f"  median gap {pct(0.5)/60:.1f}min | p90 {pct(0.9)/60:.1f}min | max {(idle_gaps[-1]/60 if n else 0):.1f}min")
print()
print("### PER-TURN CACHE-MISS SIGNATURE (cache_create > 0.5*cache_read on a turn)")
print(f"  miss-flagged turns: {miss_turns}/{total_turns} ({100*miss_turns/max(total_turns,1):.0f}%)")
print(f"  cache-create tokens spent on miss-flagged turns: {cc_tokens_on_miss:,}")
print(f"  (at 1.25x weight vs 0.1x read, these are the expensive re-cache events)")
print()
print(f"### LONG-CONTEXT TURNS (single turn re-reading >5M cached tokens): {big_ctx_turns}")
