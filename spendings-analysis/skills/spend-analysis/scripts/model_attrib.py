#!/usr/bin/env python3
"""Recover per-model token spend + timeline from raw transcripts."""
import json, glob, os
from collections import defaultdict, Counter

W = {"input": 1.0, "output": 5.0, "cache_create": 1.25, "cache_read": 0.1}
tx = glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl"))

by_model = defaultdict(Counter)          # model -> token type -> tokens
by_day_model = defaultdict(Counter)      # day -> model -> assistant msgs
model_first_last = {}                     # model -> [first_ts, last_ts]

def usage_tokens(u):
    return {
        "input": u.get("input_tokens", 0) or 0,
        "output": u.get("output_tokens", 0) or 0,
        "cache_create": u.get("cache_creation_input_tokens", 0) or 0,
        "cache_read": u.get("cache_read_input_tokens", 0) or 0,
    }

for path in tx:
    for line in open(path):
        try: r = json.loads(line)
        except: continue
        m = (r.get("message") or {})
        model = m.get("model")
        if not model: continue
        ts = r.get("timestamp") or r.get("ts") or ""
        day = ts[:10]
        by_day_model[day][model] += 1
        fl = model_first_last.setdefault(model, [ts, ts])
        if ts and ts < fl[0]: fl[0] = ts
        if ts and ts > fl[1]: fl[1] = ts
        u = m.get("usage")
        if u:
            for k, v in usage_tokens(u).items():
                by_model[model][k] += v

# ---- weighted cost share by model ----
tot_w = 0; mw = {}
for model, tk in by_model.items():
    w = sum(tk[k]*W[k] for k in tk)
    mw[model] = w; tot_w += w
print("### MODELLED COST SHARE BY MODEL (from transcript usage, weights in=1/out=5/cc=1.25/cr=0.1)")
print(f"{'model':<26}{'in':>12}{'out':>12}{'cacheCreate':>14}{'cacheRead':>15}{'cost %':>9}")
for model in sorted(mw, key=lambda x:-mw[x]):
    tk = by_model[model]
    print(f"{model:<26}{tk['input']:>12,}{tk['output']:>12,}{tk['cache_create']:>14,}{tk['cache_read']:>15,}{100*mw[model]/tot_w:>8.1f}%")

print("\n### MODEL FIRST/LAST SEEN (find the switch point)")
for model, (a, b) in sorted(model_first_last.items(), key=lambda x:x[1][0]):
    print(f"  {model:<26} {a[:19]}  ->  {b[:19]}")

print("\n### MODEL MIX BY DAY (assistant msg counts)")
allm = ["claude-opus-4-8","claude-opus-4-7","claude-opus-4-5-20251101","claude-sonnet-4-6"]
hdr = "  ".join(m.replace("claude-","")[:10] for m in allm)
print(f"  {'day':<12} {hdr}")
for day in sorted(by_day_model):
    if not day: continue
    row = "  ".join(f"{by_day_model[day].get(m,0):>10}" for m in allm)
    print(f"  {day:<12} {row}")
