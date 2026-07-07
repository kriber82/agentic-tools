#!/usr/bin/env python3
"""TTL-expiry-attributable cache re-creation (the avoidable slice).

A cache miss we can actually do something about = the ephemeral 5-min prefix TTL
lapsed, so the next request had to re-CREATE a prefix it should have re-READ.
Detect at message level: gap since previous assistant request > 5 min AND the
request re-creates content within an already-achieved prefix (HWM).
"""
import json, glob, os
from datetime import datetime

def pt(s):
    try: return datetime.fromisoformat(s.replace("Z","+00:00")).timestamp()
    except: return None
def utok(u):
    return (u.get("cache_read_input_tokens",0) or 0,
            u.get("cache_creation_input_tokens",0) or 0)

TTL=300
tot_create=0
excess_all=0                 # HWM excess (upper bound)
excess_postgap=0            # excess on msgs after >5min gap (TTL-attributable)
create_postgap=0
n_gap_msgs=0; gap_secs=[]

for path in glob.glob(os.path.expanduser("~/.claude/projects/**/*.jsonl"), recursive=True):
    in_sub="/subagents/" in path
    msgs=[]
    for line in open(path):
        try: r=json.loads(line)
        except: continue
        if r.get("type")!="assistant": continue
        u=(r.get("message") or {}).get("usage")
        if not u: continue
        ts=pt(r.get("timestamp") or r.get("ts") or "")
        cr,cc=utok(u)
        if ts is None: continue
        msgs.append((ts,cr,cc))
    msgs.sort(key=lambda x:x[0])
    hwm=0; prev_ts=None
    for ts,cr,cc in msgs:
        ctx=cr+cc
        growth=max(0,ctx-hwm)
        ex=cc-min(cc,growth)
        hwm=max(hwm,ctx)
        tot_create+=cc; excess_all+=ex
        if prev_ts is not None:
            gap=ts-prev_ts
            if gap>TTL:
                n_gap_msgs+=1; gap_secs.append(gap)
                create_postgap+=cc; excess_postgap+=ex
        prev_ts=ts

print("### CACHE_CREATE: what's an actual (TTL) miss?")
print(f"  total cache_create tokens          : {tot_create:,}")
print(f"  HWM-excess re-creation (UPPER bnd) : {excess_all:,}  ({100*excess_all/tot_create:.0f}%)")
print(f"  re-creation after a >5min gap      : {excess_postgap:,}  ({100*excess_postgap/tot_create:.0f}%)  <- TTL-attributable, avoidable")
print(f"  (all create on post-gap msgs       : {create_postgap:,}  ({100*create_postgap/tot_create:.0f}%))")
print(f"  messages preceded by >5min gap     : {n_gap_msgs}")
print()
# Avoidable slice as a share of cache-create (token-share == cost-share). The
# cold-turn signature lower bound is computed separately by cache_waste.py; the
# three estimators are expected to bracket ~20-22%.
print("### AVOIDABLE re-creation as a share of cache_create")
print(f"  TTL-attributable (avoidable)       : ~{100*excess_postgap/tot_create:.0f}%")
print(f"  upper bound (all HWM re-creation)  : ~{100*excess_all/tot_create:.0f}%")
