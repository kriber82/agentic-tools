#!/usr/bin/env python3
"""Analyse Claude Code AI spend from ~/.claude/session-logs/*.jsonl"""
import json, glob, os, math
from collections import defaultdict, Counter
from datetime import datetime

LOGDIR = os.path.expanduser("~/.claude/session-logs")
# Relative cost weights vs base input token (Anthropic Opus-style multipliers)
W = {"input": 1.0, "output": 5.0, "cache_create": 1.25, "cache_read": 0.1}

def parse_ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None

sessions = {}
for path in glob.glob(os.path.join(LOGDIR, "*.jsonl")):
    sid = os.path.basename(path)[:-6]
    recs = []
    for line in open(path):
        line = line.strip()
        if not line: continue
        try: recs.append(json.loads(line))
        except: pass
    sessions[sid] = recs

# ---------- aggregate ----------
grand_cost = 0.0
grand_tok = Counter()
per_session = []
tool_dur = defaultdict(float); tool_count = Counter()
skill_uses = Counter()
cache_risk_events = []          # (sid, tool, dur)
missing_costtok = 0; total_cost_ev = 0
missing_desc = 0; total_toolstart = 0
turns_missing_cumul = 0
first_ts = None; last_ts = None

for sid, recs in sessions.items():
    cost_total = 0.0
    tok = Counter()
    ncost = nturn = nprompt = 0
    turn_end_ts = None
    idle_gaps = []; prompt_ts_prev_turnend = None
    max_cache_read = 0
    for r in recs:
        ev = r.get("event")
        ts = r.get("ts")
        if ts:
            t = parse_ts(ts)
            if t is not None:
                if first_ts is None or t < first_ts: first_ts = t
                if last_ts is None or t > last_ts: last_ts = t
        if ev == "cost":
            total_cost_ev += 1; ncost += 1
            if "cost_per_token" not in r: missing_costtok += 1
            cost_total = max(cost_total, r.get("cost_total", 0) or 0)
        elif ev == "assistant_turn":
            nturn += 1
            d = r.get("delta_by_type") or {}
            for k, v in d.items():
                tok[k] += v
            if "cumulative_by_type" not in r: turns_missing_cumul += 1
            cum = r.get("cumulative_by_type") or {}
            max_cache_read = max(max_cache_read, cum.get("cache_read", 0))
        elif ev == "user_prompt":
            nprompt += 1
        elif ev == "tool_start":
            total_toolstart += 1
            tl = r.get("tool", "?")
            tool_count[tl] += 1
            if "desc" not in r: missing_desc += 1
            if tl == "Skill" and r.get("desc"):
                skill_uses[r["desc"][:40]] += 1
        elif ev == "tool_end":
            tl = r.get("tool", "?")
            dur = r.get("duration_s", 0) or 0
            tool_dur[tl] += dur
            if r.get("cache_risk"):
                cache_risk_events.append((sid, tl, dur))
    grand_cost += cost_total
    for k, v in tok.items(): grand_tok[k] += v
    per_session.append({
        "sid": sid, "cost": cost_total, "tok": dict(tok),
        "ncost": ncost, "nturn": nturn, "nprompt": nprompt,
        "max_cache_read": max_cache_read,
    })

print("="*70)
print(f"PERIOD: {first_ts} -> {last_ts}")
print(f"SESSIONS: {len(sessions)}   TOTAL COST: ${grand_cost:,.2f}")
days = (last_ts - first_ts).days or 1
print(f"~${grand_cost/days:,.2f}/day over {days} days")
print("="*70)

# ---------- token mix + cost attribution ----------
tot_tok = sum(grand_tok.values())
weighted = {k: grand_tok[k]*W[k] for k in grand_tok}
tot_w = sum(weighted.values())
print("\n### TOKEN MIX & MODELLED COST SHARE (weights in=1,out=5,cc=1.25,cr=0.1)")
print(f"{'type':<14}{'tokens':>16}{'tok %':>9}{'cost %':>9}")
for k in sorted(grand_tok, key=lambda x:-weighted[x]):
    print(f"{k:<14}{grand_tok[k]:>16,}{100*grand_tok[k]/tot_tok:>8.1f}%{100*weighted[k]/tot_w:>8.1f}%")
print(f"{'TOTAL':<14}{tot_tok:>16,}")

# ---------- top sessions ----------
print("\n### TOP 12 SESSIONS BY COST")
print(f"{'session':<12}{'cost':>9}{'turns':>7}{'prompts':>8}{'cost/turn':>10}{'maxCacheRead':>14}")
for s in sorted(per_session, key=lambda x:-x["cost"])[:12]:
    cpt = s["cost"]/s["nturn"] if s["nturn"] else 0
    print(f"{s['sid'][:10]:<12}${s['cost']:>7.2f}{s['nturn']:>7}{s['nprompt']:>8}${cpt:>8.2f}{s['max_cache_read']:>14,}")

# ---------- tools ----------
print("\n### TOP TOOLS BY TOTAL WALL-TIME (duration_s summed)")
print(f"{'tool':<16}{'calls':>8}{'tot_s':>12}{'avg_s':>9}")
for tl, d in sorted(tool_dur.items(), key=lambda x:-x[1])[:12]:
    c = tool_count[tl] or 1
    print(f"{tl:<16}{tool_count[tl]:>8}{d:>12.1f}{d/c:>9.2f}")

# ---------- cache risk ----------
print(f"\n### CACHE-RISK EVENTS (tool blocked >4.5min -> likely cache-create re-pay)")
print(f"count={len(cache_risk_events)}")
for sid, tl, dur in sorted(cache_risk_events, key=lambda x:-x[2])[:15]:
    print(f"  {sid[:10]} {tl:<12} {dur:>8.1f}s ({dur/60:.1f}min)")

# ---------- skills ----------
print(f"\n### SKILL INVOCATIONS (top 15)")
for sk, c in skill_uses.most_common(15):
    print(f"  {c:>4}  {sk}")

# ---------- gaps ----------
print(f"\n### LOG GAPS / DATA QUALITY")
print(f"  model field logged anywhere?           NO (0 records carry a model id)")
print(f"  cost events missing cost_per_token:    {missing_costtok}/{total_cost_ev} ({100*missing_costtok/max(total_cost_ev,1):.0f}%)")
print(f"  tool_start missing desc:               {missing_desc}/{total_toolstart} ({100*missing_desc/max(total_toolstart,1):.0f}%)")
print(f"  assistant_turn missing cumulative:     {turns_missing_cumul}")
