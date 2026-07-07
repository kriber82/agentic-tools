#!/usr/bin/env python3
"""Miss vs first-write, per-message from transcripts (bounded, clean).

Per assistant request the API reads the longest cached prefix (cache_read) and
writes the new suffix (cache_create). Conversation is append-only, so the cached
prefix should only GROW. Track a per-session high-water mark (HWM) of the largest
context (cache_read+cache_create) ever seen:
  - legit first-write on a msg = growth beyond HWM (new territory, unavoidable)
  - excess = cache_create beyond that growth = re-writing content already within a
    previously-cached prefix = a MISS (TTL expiry; prefix had to be rebuilt).
"""
import json, glob, os

def utok(u):
    return (u.get("cache_read_input_tokens",0) or 0,
            u.get("cache_creation_input_tokens",0) or 0)

tot_create=tot_read=legit=excess=0
# split main vs subagent
by_role={"main":[0,0,0], "subagent":[0,0,0]}  # create, legit, excess

for path in glob.glob(os.path.expanduser("~/.claude/projects/**/*.jsonl"), recursive=True):
    in_sub = "/subagents/" in path
    msgs=[]
    for line in open(path):
        try: r=json.loads(line)
        except: continue
        if r.get("type")!="assistant": continue
        m=r.get("message") or {}
        u=m.get("usage")
        if not u: continue
        ts=r.get("timestamp") or r.get("ts") or ""
        role = "subagent" if (in_sub or r.get("isSidechain")) else "main"
        cr,cc=utok(u)
        msgs.append((ts,cr,cc,role))
    msgs.sort(key=lambda x:x[0])
    hwm=0
    for ts,cr,cc,role in msgs:
        ctx=cr+cc
        growth=max(0, ctx-hwm)
        lg=min(cc, growth)
        ex=cc-lg
        hwm=max(hwm,ctx)
        tot_create+=cc; tot_read+=cr; legit+=lg; excess+=ex
        by_role[role][0]+=cc; by_role[role][1]+=lg; by_role[role][2]+=ex

print("### CACHE_CREATE DECOMPOSITION (all transcripts, per-message HWM model)")
print(f"  total cache_create : {tot_create:,}")
print(f"  legit first-write  : {legit:,}  ({100*legit/tot_create:.0f}%)")
print(f"  EXCESS (misses)    : {excess:,}  ({100*excess/tot_create:.0f}%)")
print(f"  read:create ratio  : {tot_read/max(tot_create,1):.1f}:1")
print()
print("### by role")
for role,(cc,lg,ex) in by_role.items():
    if cc==0: continue
    print(f"  {role:<9} create={cc:>13,}  first-write={100*lg/cc:>3.0f}%  miss={100*ex/cc:>3.0f}% ({ex:,})")
print()
miss_frac = excess/tot_create
print("### cache-write cost split (share of cache_create; token-share == cost-share)")
print(f"  actual cache misses   ≈ {100*miss_frac:.0f}%")
print(f"  unavoidable 1st-write ≈ {100*(1-miss_frac):.0f}%")
print()
print("NOTE: a 'miss' here = cache_create re-writing content within an already-achieved")
print("prefix (append-only convo => almost always the 5-min TTL lapsing). It does NOT")
print("include the *read-side* penalty of a miss (re-reading a rebuilt prefix), so the")
print("true cost of misses is somewhat higher than this cache_create-only slice.")
