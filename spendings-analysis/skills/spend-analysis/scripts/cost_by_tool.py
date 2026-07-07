#!/usr/bin/env python3
"""Retrospective: attribute cost_delta to the tool whose completion preceded it.
Rough (statusline cost is sparse/cumulative) but shows which tools bracket spend."""
import json, glob, os
from datetime import datetime
from collections import defaultdict

def pts(s):
    try: return datetime.fromisoformat(s.replace("Z","+00:00")).timestamp()
    except: return None

by_tool_cost = defaultdict(float)     # tool -> summed cost_delta attributed
by_tool_n = defaultdict(int)
unattributed = 0.0

for path in glob.glob(os.path.expanduser("~/.claude/session-logs/*.jsonl")):
    ev=[]
    for line in open(path):
        line=line.strip()
        if not line: continue
        try: r=json.loads(line)
        except: continue
        t=pts(r.get("ts",""))
        if t is None: continue
        r["_t"]=t; ev.append(r)
    ev.sort(key=lambda x:x["_t"])
    # walk; track most recent tool_end before each cost event with delta>0
    last_tool_end=None
    for r in ev:
        e=r.get("event")
        if e=="tool_end":
            last_tool_end=r.get("tool")
        elif e=="cost":
            d=r.get("cost_delta",0) or 0
            if d>0:
                if last_tool_end:
                    by_tool_cost[last_tool_end]+=d; by_tool_n[last_tool_end]+=1
                else:
                    unattributed+=d

tot=sum(by_tool_cost.values())+unattributed
print("### COST_DELTA ATTRIBUTED TO PRECEDING TOOL (retrospective, rough)")
print(f"{'tool':<20}{'$ attributed':>14}{'% ':>7}{'n intervals':>13}{'$/interval':>12}")
for tl,c in sorted(by_tool_cost.items(), key=lambda x:-x[1])[:15]:
    n=by_tool_n[tl] or 1
    print(f"{tl:<20}{c:>14.2f}{100*c/tot:>6.1f}%{n:>13}{c/n:>12.3f}")
print(f"{'(no preceding tool)':<20}{unattributed:>14.2f}{100*unattributed/tot:>6.1f}%")
print(f"{'TOTAL':<20}{tot:>14.2f}")
