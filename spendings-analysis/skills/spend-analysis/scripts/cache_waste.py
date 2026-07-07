#!/usr/bin/env python3
"""How much cache_create is UNAVOIDABLE first-write vs AVOIDABLE re-creation (misses)?

Model of prompt caching: each turn reads the longest cached prefix (cache_read)
and writes the new suffix (cache_create). Writing a token to cache costs 1.25x;
reading it later 0.1x. So the *necessary* lifetime cache_create for a session is
~the peak context ever reached (every token must be written to cache at least
once). cache_create BEYOND that peak = re-creation of content that was already
cached = a miss (TTL expiry, breakpoint churn, or compaction regrow).

Two bounds:
  - EXCESS (floor-based): total_create - peak_context   -> upper bound on waste
  - SIGNATURE (per-turn): cache_create on turns where create > 0.5*read
                          (a healthy turn's create is tiny vs read) -> lower bound
Idle attribution: of excess, how much sits on turns preceded by a >5min gap.
"""
import json, glob, os
from datetime import datetime

def pts(s):
    try: return datetime.fromisoformat(s.replace("Z","+00:00")).timestamp()
    except: return None

W_CREATE, W_READ = 1.25, 0.1

tot_create = tot_read = 0
necessary = 0            # sum of per-session peak context
excess_floor = 0         # total_create - peak, summed (>=0 per session)
sig_waste = 0            # cache_create on miss-signature turns
sig_waste_idle = 0       # of which, preceded by >5min idle
n_sessions = 0

for path in glob.glob(os.path.expanduser("~/.claude/session-logs/*.jsonl")):
    turns = []
    prev_end = None
    recs = []
    for line in open(path):
        line=line.strip()
        if not line: continue
        try: recs.append(json.loads(line))
        except: pass
    # collect turns with idle gap (prompt_ts - prev_turn_end)
    prompts = [r for r in recs if r.get("event")=="user_prompt"]
    s_create=s_read=0; peak=0
    last_turn_end=None
    # build ordered events for idle calc
    ordered = [r for r in recs if r.get("ts")]
    ordered.sort(key=lambda r: pts(r["ts"]) or 0)
    prev_turn_end_ts=None
    last_prompt_gap=None
    for r in ordered:
        ev=r.get("event")
        if ev=="user_prompt":
            r["_gap"] = None
            t=pts(r.get("ts"))
            if t and prev_turn_end_ts:
                r["_gap"] = t-prev_turn_end_ts
        elif ev=="assistant_turn":
            d=r.get("delta_by_type") or {}
            cc=d.get("cache_create",0) or 0; cr=d.get("cache_read",0) or 0
            inp=d.get("input",0) or 0
            s_create+=cc; s_read+=cr
            ctx = cc+cr+inp
            if ctx>peak: peak=ctx
            # nearest preceding prompt gap
            gap=None
            # find last prompt before this turn
            # (ordered walk: track most recent prompt gap)
            gap = last_prompt_gap
            if cc > 0.5*max(cr,1):
                sig_waste += cc
                if gap is not None and gap>300: sig_waste_idle += cc
            prev_turn_end_ts = pts(r.get("ts"))
        if ev=="user_prompt":
            last_prompt_gap = r.get("_gap")
    if s_create==0 and s_read==0: continue
    n_sessions+=1
    tot_create+=s_create; tot_read+=s_read
    necessary+=peak
    excess_floor += max(0, s_create - peak)

# guard for the very first prompt loop var
print(f"sessions with cache activity: {n_sessions}")
print(f"total cache_create tokens : {tot_create:,}")
print(f"total cache_read tokens   : {tot_read:,}")
print(f"overall read:create ratio : {tot_read/max(tot_create,1):.1f}:1  (higher = healthier)")
print()
print("### NECESSARY vs EXCESS cache_create")
print(f"  necessary (Σ peak context, one-time build) : {necessary:,}  ({100*necessary/tot_create:.0f}% of create)")
print(f"  EXCESS / re-creation (floor, upper bound)  : {excess_floor:,}  ({100*excess_floor/tot_create:.0f}% of create)")
print(f"  miss-SIGNATURE waste (lower bound)         : {sig_waste:,}  ({100*sig_waste/tot_create:.0f}% of create)")
print(f"     of which preceded by >5min idle         : {sig_waste_idle:,}  ({100*sig_waste_idle/max(sig_waste,1):.0f}% of signature waste)")
print()
# Report the AVOIDABLE slice as a share of cache-create (every cache_create token
# costs the same rate, so token-share == cost-share). Multiply by your own
# cache-create cost from spend_analysis.py if you want an absolute figure.
print("### AVOIDABLE re-creation as a share of cache_create")
lo = 100 * sig_waste / tot_create
hi = 100 * excess_floor / tot_create
print(f"  lower bound (signature): ~{lo:.0f}% of cache-create")
print(f"  upper bound (floor)    : ~{hi:.0f}% of cache-create")
print(f"  => roughly {lo:.0f}–{hi:.0f}% of cache-create is re-creation, not first-write")
