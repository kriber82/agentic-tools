#!/usr/bin/env python3
"""Cost of subagent (sidechain) turns by model + Opus->Sonnet counterfactual."""
import json, glob, os
from collections import defaultdict

# Published per-token USD rates (list price; your actual rates may differ but ratios hold).
RATE = {
  "opus":   {"input":15e-6, "output":75e-6, "cache_create":18.75e-6, "cache_read":1.5e-6},
  "sonnet": {"input":3e-6,  "output":15e-6, "cache_create":3.75e-6,  "cache_read":0.3e-6},
}
def fam(model):
    if "opus" in model: return "opus"
    if "sonnet" in model or "haiku" in model: return "sonnet"
    return None

def utok(u):
    return {"input":u.get("input_tokens",0) or 0,
            "output":u.get("output_tokens",0) or 0,
            "cache_create":u.get("cache_creation_input_tokens",0) or 0,
            "cache_read":u.get("cache_read_input_tokens",0) or 0}

def cost(tok, family):
    return sum(tok[k]*RATE[family][k] for k in tok)

agg = defaultdict(lambda: defaultdict(float))   # (side, model) -> tok/cost
for path in glob.glob(os.path.expanduser("~/.claude/projects/**/*.jsonl"), recursive=True):
    in_subdir = "/subagents/" in path
    for line in open(path):
        try: r=json.loads(line)
        except: continue
        if r.get("type")!="assistant": continue
        m=(r.get("message") or {})
        model=m.get("model"); u=m.get("usage")
        if not model or not u: continue
        f=fam(model)
        if not f: continue
        side = bool(r.get("isSidechain")) or in_subdir
        tok=utok(u)
        key=(side, model)
        for k,v in tok.items(): agg[key][k]+=v
        agg[key]["_cost"]+=cost(tok,f)

print("### MODELLED $ BY (role, model) — list-price, all transcripts/projects")
print(f"{'role':<10}{'model':<22}{'msgs?':>0}{'est_cost':>12}{'output_tok':>14}{'cache_rd_tok':>16}")
grand=0
for (side,model) in sorted(agg, key=lambda k:-agg[k]['_cost']):
    a=agg[(side,model)]; grand+=a['_cost']
    role="subagent" if side else "main"
    print(f"{role:<10}{model:<22}{a['_cost']:>12.2f}{int(a['output']):>14,}{int(a['cache_read']):>16,}")
print(f"{'TOTAL':<32}{grand:>12.2f}")

# ---- counterfactual: subagent turns currently on OPUS moved to SONNET ----
sub_opus_cost=0.0; sub_opus_tok=defaultdict(float)
for (side,model),a in agg.items():
    if side and fam(model)=="opus":
        sub_opus_cost+=a["_cost"]
        for k in ("input","output","cache_create","cache_read"): sub_opus_tok[k]+=a[k]
sonnet_equiv=cost(sub_opus_tok,"sonnet")
print("\n### COUNTERFACTUAL: subagent turns now on Opus -> Sonnet")
print(f"  current subagent-on-Opus modelled cost: ${sub_opus_cost:,.2f}")
print(f"  same tokens at Sonnet rates:            ${sonnet_equiv:,.2f}")
print(f"  estimated saving:                       ${sub_opus_cost-sonnet_equiv:,.2f}  ({100*(1-sonnet_equiv/sub_opus_cost):.0f}% of subagent-Opus)")
print(f"  as % of all modelled spend:             {100*(sub_opus_cost-sonnet_equiv)/grand:.1f}%")
