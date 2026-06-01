# Pass Overlap: Dedup + Responsibility Evolution — Design

**Date:** 2026-06-01
**Extends:** `code-review-opinionated` skill (see 2026-06-01-multi-pass-code-review-design.md)
**Type:** Orchestrator feature + per-pass frontmatter addition

## Problem

Multiple review passes overlap. Two consequences:

1. **Duplicate findings** — the same issue caught by two passes produces two summary
   rows (clutter; the headache the single-file design set out to remove).
2. **Unclear responsibility boundaries over time** — passes were added organically;
   some genuinely overlap. We want help *evolving* the pass set toward cleaner
   separation, based on evidence, without losing findings a pass uniquely catches.

This is **authoring-time** evolution support (help the author improve passes over
time), not runtime lane-keeping. The author always decides; the system only
measures and flags.

## Core insight

Both features ride one mechanism: the orchestrator's **merge step** — deciding that
findings from different passes are the same finding. That decision drives dedup
(collapse rows) and produces the overlap signal (which concerns collided).

**Sameness criterion:** two findings are the same iff
**same location AND each one's fix would also resolve the other** (a single code
change makes both disappear). Behavioral, not topical.

## Set model (the analysis this enables)

For any shared concept R that passes A and B both touch, each review partitions
R-findings into: **A∩B** (both caught), **A\B** (only A), **B\A** (only B).

- **Overlap** = size of A∩B (redundancy of the intersection → dedup).
- **Safe one-sided removal** = **directional subsumption**: if, across N reviews,
  **A\B(R) is empty while B\A(R) is non-empty**, B subsumes A on R → removing R
  from A is licensed. Mutual equivalence is not required — only the removed side's
  unique set must be empty.

Three things that make this inherently human-judged (system flags, never decides):

1. **Longitudinal, not per-run** — subsumption is a claim across many reviews; one
   review proves nothing. Requires cross-review persistence.
2. **B\A is ambiguous** — "B's responsibility covers it and A's doesn't" (clean
   boundary) vs "A's responsibility covers it too but A missed it this run" (recall
   failure) are *identical in the data*. Only a human reading the finding can tell.
3. **Absence of A\B is not proof** — finite codebase sample; A's unique value may
   live in code not yet reviewed. "Safe" is never proven, only "empty across last N."

## The four repair moves

Removal is one of four; the evidence points to which:

- **dedup-only** — overlap exists but both passes contribute unique findings; just
  merge rows at runtime, change nothing.
- **remove-one-side** — directional subsumption holds; drop concept R from the
  subsumed pass.
- **sharpen** — both have non-empty unique sets but collide on a shared sub-part;
  tighten each pass's R-instruction so they stop colliding while keeping their
  distinct angles.
- **split** — R deserves its own pass.

## Feature 1 — Dedup (runtime, per review)

When the orchestrator merges same-findings, it writes **one** summary row whose
provenance lists **all source finding IDs** (not just pass names):

`sources: GEN-03, PROP-06, SCREAM-01`

Each source pass's detail file keeps its full prose. When fixing a merged finding,
the reader consults all referenced entries so each pass's nuance is incorporated.

**Summary table change:** the `pass` column becomes a `sources` column holding the
list of contributing finding IDs. (Single-source findings list one ID.)

## Feature 2 — Concern tagging (log-time, per-pass vocabulary)

- **Specific passes declare their concerns** as a stable, enumerated list in
  frontmatter (`concerns: [...]`). Each finding carries a `concern` from its own
  pass's vocabulary. **No global concept map** — cross-pass concepts are clustered
  by the human at decision time.
- **No on-the-fly tagging** — declared only (stability across runs is the whole
  point).
- **Catch-all passes are exempt** (e.g. `general-review`). They declare no
  concerns. When a collision involves a catch-all finding, the orchestrator records
  its concern as the **pass name** (`general-review:general-review`). Consequence:
  the catch-all participates in collision logging but, because its "concern" is its
  own name, can never appear as a concept two *specific* passes share — so it is
  structurally excluded from remove/sharpen/split (correct: you never carve up the
  catch-all).

Concern field states: **declared** (specific passes) · **absent → pass-name
fallback** (catch-all passes).

Note: `code-properties` (its property list) and `screaming-architecture` (its three
tests) already contain their concern vocabularies; tagging formalizes them.

## Feature 3 — Overlap log (medium persistence)

One append-only Markdown file: **`docs/reviews/_overlap-log.md`**

(Leading underscore sorts it above dated review dirs and marks it meta;
human-readable for the decision-time read-through.)

Per review, the orchestrator appends facts it already computed (no aggregation at
write time):

```
## 2026-06-01 | checkout-retry | scope <BASE>..<HEAD> | passes: [general-review, code-properties, screaming-architecture]
collisions_total_running: 47

### Collisions (count + merged summary IDs)
- code-properties:honest-names × screaming-architecture:vocabulary-audit — 2  [NAME-88, NAME-31]
- general-review:general-review × code-properties:resilience — 1  [RES-09]

### Unmatched (counts only)
- general-review:general-review — 4
- code-properties:correct — 5
- screaming-architecture:closeness — 1
```

**Logging rules (these make counts lossless for subsumption):**

- **Each merge group is logged as ONE tuple carrying its full participant set**
  (all `pass:concern` participants), never decomposed into pairwise pairs. This is
  a hard requirement and is **load-bearing** — it is what makes count-only logging
  reconstructible (see `overlap-analysis.md` for the math that depends on it). Do
  not "simplify" to pairwise logging.
- **Collisions:** per full-participant tuple, store a **count** and the list of
  **merged summary IDs** (traceability; escape hatch for the rare 3+ pass case).
- **Unmatched:** **counts only**, per `pass:concern` (the findings themselves live
  in that review's `summary.md`).
- `collisions_total_running` — running counter across all reviews (drives the
  auto-nudge; see below).

**Reconstructibility** is proven in `overlap-analysis.md` (the decision-time
reference). Summary: counts per full-participant tuple plus unmatched counts are
sufficient to recover A∩B, A\B, and B\A for any pass pair by arithmetic across
tuples. The orchestrator does **not** need this math to log correctly — the
logging rules above are mechanically complete on their own.

**Accepted losses at medium** (recoverable later by joining merged IDs to the
review summaries; heavy-persistence territory): spatial distribution of collisions,
and severity-correlation of collisions.

## Feature 4 — Nudges & triggers

**Per-review footer** (when ≥1 collision occurred) — gentle, factual, top-3 tuples
with overflow:

```
Overlap this review: 2 collisions · unique — general-review: 4, code-properties: 5, screaming-architecture: 1
Top colliding concerns: honest-names×vocabulary-audit (2), resilience×correct (1)
```

**Auto-offer trigger** — when `collisions_total_running` crosses **100** (fixed for
now; not configurable). Driven by accumulated collisions (a better proxy for
"enough evidence per concept-pair" than session count). Top-3 tuples + `+N more`:

```
100+ collisions logged. Heaviest overlaps: honest-names×vocabulary-audit (23), resilience×correct (14), +5 more pairs.
Run overlap analysis? [now / remind next time / remind later]  (or ask "analyze pass overlap" anytime)
```

Offer responses:
- **now** — run decision-time analysis immediately.
- **remind next time** — *keep* the counter (re-offers next review with collisions).
- **remind later** — *reset* the counter to 0 (snooze a full cycle).

**Manual trigger** — "analyze pass overlap" works anytime, regardless of counter.

## Feature 5 — Decision-time analysis (human-driven, rare)

**This procedure lives in a separate file `overlap-analysis.md`, loaded only when
triggered** — not inline in SKILL.md. Rationale: the orchestrator needs only the
dedup + logging contract on every run (mechanically complete on its own); the
analysis knowledge (clustering, reconstructibility math, subsumption, the four
moves) is heavy and used rarely, so keeping it out of the every-run context keeps
SKILL.md lean. `overlap-analysis.md` also holds the reconstructibility proof that
the load-bearing full-participant-set logging rule depends on.

When triggered (auto-offer "now", or manual "analyze pass overlap"), the agent
loads `overlap-analysis.md` and, with the user:

1. Read the accumulated `_overlap-log.md`.
2. Cluster the **stable concern labels** (small finite set — the union of declared
   concerns) into cross-pass concepts. Clustering is the human judgment; the small
   stable label set makes it tractable (≈dozens of labels, not hundreds of
   findings).
3. Per concept R, compute the set tallies (arithmetic above) across the logged
   reviews; assess directional subsumption and unique-set sizes.
4. The agent **presents candidates with evidence and recommends one of the four
   moves**; the **user decides**. The agent does **not** edit any pass on its own
   (consistent with the skill's autonomy gates). B\A ambiguity is surfaced, not
   resolved by the agent.

"Safe to remove" is reported as "A\B(R) empty across last N reviews of R" — the
user judges whether N is sufficient.

## Changes to existing artifacts

- **SKILL.md (orchestrator):** add the merge/dedup step (sources = source IDs);
  write the per-review log entry; emit the per-review footer; check the auto-offer
  threshold; document the "analyze pass overlap" manual trigger and point to
  `overlap-analysis.md` for the decision-time procedure. Inline content stays
  limited to the dedup + logging contract + nudges (the every-run knowledge).
- **New file `overlap-analysis.md`** (in the skill dir, loaded only on trigger):
  the decision-time procedure, the reconstructibility proof, subsumption criteria,
  and the four moves.
- **Summary table:** `pass` column → `sources` column (list of source finding IDs).
- **Pass frontmatter:** add `concerns: [...]` to specific passes
  (`code-properties`, `screaming-architecture`); `general-review` stays exempt.
- **New file:** `docs/reviews/_overlap-log.md` (created on first collision).

## Out of scope (future / heavy persistence)

- Exact pairwise subsumption stats computed automatically.
- Per-location collision data, spatial distribution, severity correlation.
- Runtime lane-keeping (telling passes what others own) — explicitly deferred.

## Open items to resolve during build

- Exact concern vocabularies to declare for `code-properties` and
  `screaming-architecture` (derive from their existing lists).
