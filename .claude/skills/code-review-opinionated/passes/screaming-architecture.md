---
name: screaming-architecture
description: Per-file intention-clarity review — does the code's local text scream its business mission? Walks changed production files from construction root toward the edges, applying the Stranger / Substitution / Vocabulary tests, and proposes code-level (not comment) refactorings that make intent legible. Overlaps somewhat with general code-quality review and can overshoot — calibration guidance included.
id_prefix: SCREAM
estimates_effort: true
---

# Pass: Screaming Architecture

For each **production code file changed in the branch**, judge whether the code's
*local text alone* communicates its business mission, and propose code changes
that close any gap. Process files in dependency order: **start at the
construction root / main and work toward the edges of the system.**

## Per-file procedure

For each changed production file (and, where useful, each method), apply these
tests using **only the text visible at this level** (header + body, no jumping to
referenced types or bodies). Output the per-file results before proceeding to the
next file.

### 1. The Stranger Test (reconstruction)
Imagine a developer who has never seen this codebase, the repo's name, or any
docs. From the text alone, have them write one sentence:
*"This code verbs a noun from source to destination."* If any of those four slots
can't be filled with a concrete, domain-specific word — or could be filled
equally well with several unrelated guesses — the mission is not screaming. Note
exactly which slot is missing.

### 2. The Substitution Test (genericity probe)
Could this code, with no changes other than renaming a few function calls,
plausibly belong to a completely different system (invoice processor, email
sender, log shipper, ETL job)? If yes, list two or three other domains it could
pass for. The more domains it fits, the less it screams.

### 3. The Vocabulary Audit (concrete nouns)
List the concrete nouns and verbs that appear in the visible text. Then list the
concrete nouns and verbs you'd expect if this code were doing what its position
in the system suggests. Anything in the second list missing from the first is a
leak in the scream — the mission word is implied but not spoken.

### 4. Intention-communication improvements
If gaps were identified, propose refactorings that reveal the method's/file's
intention better. **The fixes must be code changes — comments or docstrings are
not a viable option.** Goal: reading only the local text, the Stranger Test
sentence and the actual business mission reach a near-100% match.
- a. Local improvements
- b. Broader-scope improvements

## Calibration — avoid overshoot

This pass tends to overshoot. Guard against it:
- Only raise a finding when the Stranger reconstruction **genuinely diverges**
  from the real mission. Code that already screams needs no finding — say so and
  move on.
- Do not propose renames/refactors purely for taste when intent is already clear.
- A finding is the **gap**, not the aesthetic preference. If you can't name which
  slot (verb / noun / source / destination) is missing, there is no finding.
- Prefer the smallest change that closes the gap; reserve broader-scope
  refactors for genuine, repeated leaks.

## Mapping to finding entry

Each surviving improvement proposal becomes a finding.

- `native_metric`: `intention-clarity priority (closeness-to-top × local-impact ÷ change-complexity)`
- `native_score`: the value of that product for this finding (qualitative is fine:
  `high`/`med`/`low`, or a number) — higher = more central + more impact + cheaper.
  Closeness-to-top matters because top-level/abstract files hold the most stable,
  relevant business logic and most need to be expressive.
- `confidence`: your real read that the intent gap is genuine (not taste).
- `effort`: the **change-complexity** estimate for the proposed refactor (this
  pass estimates effort — `estimates_effort: true`).
- `impact-evidence`: the concrete gap — which slot/word is missing and what the
  stranger wrongly reconstructs — e.g. "stranger reads `process(data)` as generic
  ETL; real mission is settling payouts".

Do **not** emit a cross-pass impact number; the orchestrator assigns impact with
all findings in view.

## Detail file schema

```markdown
# Screaming Architecture — findings

scope: <BASE>..<HEAD>

<!-- optional: brief per-file pass notes, root → edges, for traceability -->

## SCREAM-01 — <short title>
- native_metric: intention-clarity priority (closeness-to-top × local-impact ÷ change-complexity)
- native_score: <high | med | low | number>
- confidence: <low | medium | high>
- effort: <low | medium | high>
- impact-evidence: <the concrete gap: missing slot + stranger's wrong read>

<prose: file:line, the failing test(s), proposed code change (local and/or broader), why it closes the gap>

## SCREAM-02 — ...

<!-- end:screaming-architecture -->
```

## Return to orchestrator

Compact row-summary, one line per finding:
`id | title | native_score | confidence | effort | impact-evidence`.
Regenerable from the detail file headers; ephemeral.

## Reminder

Findings only. The parent skill's autonomy gates apply: do not edit, stage,
commit, or merge any file outside `docs/reviews/<slug>/`. Do not apply the
refactorings — propose them.
