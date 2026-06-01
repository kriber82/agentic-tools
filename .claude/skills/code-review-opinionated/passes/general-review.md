---
name: general-review
description: Broad senior-engineer code review of the changeset — plan alignment, code quality, architecture, testing, production readiness. Wraps the superpowers requesting-code-review skill.
id_prefix: GEN
estimates_effort: false
---

# Pass: General Review

Runs a broad code review over the review scope by dispatching the
`superpowers:requesting-code-review` reviewer, then records each issue as a
finding in this skill's standard schema.

## What to do

1. **Scope.** You are given `BASE_SHA` and `HEAD_SHA` (the review scope) and the
   output path `docs/reviews/<slug>/general-review.md`.
2. **Run the review.** Dispatch the reviewer exactly as `superpowers:requesting-code-review`
   prescribes — fill its `code-reviewer.md` template with:
   - `{DESCRIPTION}` — a one-line summary of the changeset (derive from the diff/commits).
   - `{PLAN_OR_REQUIREMENTS}` — the plan/requirements if known; otherwise state "ad-hoc
     changeset, no written plan — review against general quality and correctness."
   - `{BASE_SHA}` / `{HEAD_SHA}` — the review scope.
3. **Map each returned Issue to a finding** (see mapping below). Ignore *Strengths* and
   *Recommendations* for the findings table — they are not findings. (You may keep a one-line
   note of Recommendations in the prose if genuinely actionable, but do not create finding rows
   for them.)
4. **Write the detail file** at the given path in the schema below, ending with the completion
   marker.

## Mapping reviewer output → finding entry

The reviewer's native metric is **severity** (Critical / Important / Minor). Record it as the
native metric; do not invent an impact number (the orchestrator assigns cross-pass impact).

| Reviewer severity | `native_score` | `confidence` (default) |
|-------------------|----------------|------------------------|
| Critical          | `critical`     | high — only lower if the reviewer hedged |
| Important         | `important`    | medium-high |
| Minor             | `minor`        | medium |

- `native_metric`: `severity (Critical/Important/Minor)`
- `confidence`: start from the table, then adjust to reflect how certain the reviewer's wording
  was ("definitely" vs "might"). This is your real read of whether the finding is true, not a
  restatement of severity.
- `effort`: **omit** — this pass does not estimate effort (`estimates_effort: false`).
- `impact-evidence`: a short concrete note grounding why it matters, drawn from the reviewer's
  "why it matters" — e.g. "silent undefined order id reaches checkout", not "important issue".

## Detail file schema

```markdown
# General Review — findings

scope: <BASE_SHA>..<HEAD_SHA>

## GEN-01 — <short title>
- native_metric: severity (Critical/Important/Minor)
- native_score: critical | important | minor
- confidence: <low | medium | high>
- impact-evidence: <one concrete phrase>

<prose: file:line reference, what's wrong, why it matters, proposed change/refactor>

## GEN-02 — <short title>
...

<!-- end:general-review -->
```

## Return to orchestrator

Return a compact row-summary (do not persist separately): one line per finding —
`id | title | native_score | confidence | impact-evidence`. This is regenerable from the detail
file headers; it exists only to save the orchestrator from re-parsing.

## Reminder

This pass produces findings only. The autonomy gates in the parent skill apply: do not edit,
stage, commit, or merge any file outside `docs/reviews/<slug>/`.
