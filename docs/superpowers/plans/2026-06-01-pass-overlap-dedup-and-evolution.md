# Pass Overlap: Dedup + Responsibility Evolution — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deduplication of overlapping findings and authoring-time pass-responsibility evolution support to the `code-review-opinionated` skill.

**Architecture:** This feature is *prose instructions for an orchestrator agent*, not executable code. The orchestrator's merge step drives both dedup (collapse duplicate rows into one with all source IDs) and an append-only overlap log (`docs/reviews/_overlap-log.md`) recording collisions and unmatched counts. A separate `overlap-analysis.md`, loaded only on trigger, holds the rare decision-time analysis (clustering, subsumption math, four repair moves). Specific passes declare `concerns:` in frontmatter; catch-all passes are exempt and fall back to their pass name.

**Tech Stack:** Markdown skill files (`SKILL.md`, `passes/*.md`, new `overlap-analysis.md`). No runtime/test framework. **Verification is by application-test:** dispatch a subagent that follows ONLY the written instructions against a fixture, then assert the artifact it produces (merged table, log entry, analysis) is correct.

**Spec:** `docs/superpowers/specs/2026-06-01-pass-overlap-dedup-and-evolution-design.md`

---

## File Structure

- **Modify** `.claude/skills/code-review-opinionated/SKILL.md` — summary table column change (`pass` → `sources`); new "Deduplication" subsection; new "Overlap Log" section (logging contract); new "Overlap Nudges" section; manual-trigger line + pointer to `overlap-analysis.md`.
- **Modify** `.claude/skills/code-review-opinionated/passes/code-properties.md` — add `concerns:` frontmatter.
- **Modify** `.claude/skills/code-review-opinionated/passes/screaming-architecture.md` — add `concerns:` frontmatter.
- **Create** `.claude/skills/code-review-opinionated/overlap-analysis.md` — decision-time procedure, reconstructibility proof, subsumption criteria, four moves.

`general-review.md` is intentionally NOT modified (catch-all, exempt from concern tagging).

---

## Task 1: Declare concerns on the specific passes

**Files:**
- Modify: `.claude/skills/code-review-opinionated/passes/code-properties.md` (frontmatter, lines 1-6)
- Modify: `.claude/skills/code-review-opinionated/passes/screaming-architecture.md` (frontmatter, lines 1-6)

Concern vocabularies are derived from each pass's existing content (spec open item). Use kebab-case labels.

- [ ] **Step 1: Add `concerns:` to code-properties frontmatter**

Insert a `concerns:` list into the existing frontmatter of `passes/code-properties.md`, after the `estimates_effort: false` line and before the closing `---`. Derive labels from its property list:

```yaml
concerns: [correct, secure, resilient, reveals-intent, self-contained, honest-names, fits-in-head, one-abstraction-level, semantic-grouping, cohesive, explicit, symmetric, directed, idiomatic]
```

- [ ] **Step 2: Add `concerns:` to screaming-architecture frontmatter**

Insert into the existing frontmatter of `passes/screaming-architecture.md`, after `estimates_effort: true` and before the closing `---`. Derive from its three tests + improvement axes:

```yaml
concerns: [stranger-reconstruction, substitution-genericity, vocabulary-audit]
```

- [ ] **Step 3: Add a per-finding `concern` field instruction to each modified pass body**

In `passes/code-properties.md`, the finding schema already has a `property:` line. Add immediately after it in the schema block (the fenced block under "## Detail file schema"):

```
- concern: <one label from this pass's `concerns:` frontmatter list>
```

And add a sentence under "## Mapping to finding entry" (after the `impact-evidence` bullet):

```
- `concern`: the single `concerns:` label (from this pass's frontmatter) that best classifies this finding. Used for cross-pass overlap analysis; must be one of the declared labels.
```

In `passes/screaming-architecture.md`, add the same `concern` line to its detail-file schema block (after the `impact-evidence` line) and the same mapping sentence (after its `impact-evidence` bullet), referencing its own `concerns:` list.

- [ ] **Step 4: Application-test the concern tagging**

Dispatch a subagent with the full modified `code-properties.md` content and a small fixture diff (reuse the orderService.ts fixture pattern: a swallowed `catch {}` + a single-letter name). Instruct it to produce its detail file per the pass.

Run (conceptually): subagent returns detail file.
Expected: every finding includes a `concern:` line whose value is one of the declared labels (e.g. the swallowed error → `resilient`; the single-letter name → `honest-names` or `reveals-intent`). No finding uses a label outside the list.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/code-review-opinionated/passes/code-properties.md .claude/skills/code-review-opinionated/passes/screaming-architecture.md
git commit -m "feat(code-review): declare per-pass concerns for overlap analysis"
```

---

## Task 2: Dedup — merge same-findings into one row with all source IDs

**Files:**
- Modify: `.claude/skills/code-review-opinionated/SKILL.md` (Summary Table section, lines 91-97; add a Deduplication subsection after it)

- [ ] **Step 1: Change the summary table column from `pass` to `sources`**

Replace the column list in the "## Summary Table" section (line 95):

Old:
```
`priority` (sort key) · `id` · `pass` · `title` · `impact` · `confidence` · `effort` · `native_score` · `status` · `rationale`
```

New:
```
`priority` (sort key) · `id` · `sources` · `title` · `impact` · `confidence` · `effort` · `native_score` · `status` · `rationale`
```

- [ ] **Step 2: Add the Deduplication subsection**

Insert immediately after the "## Summary Table" section (after line 97), before "## State Tracking":

```markdown
## Deduplication

Before writing the table, merge findings that are **the same finding**.

**Sameness criterion:** two findings are the same iff they are at the **same
location** AND **each one's fix would also resolve the other** (a single code
change makes both disappear). This is behavioral, not topical — two findings about
"naming" at different lines are NOT the same; a bug and a rename at the same line
are NOT the same (different fixes).

For each merge group:
- Write **one** summary row.
- The `sources` column lists **all** contributing finding IDs, e.g.
  `GEN-03, PROP-06, SCREAM-01`. A single-source finding lists one ID.
- Each source pass's detail file keeps its full prose unchanged. When acting on a
  merged finding, read every referenced entry so each pass's nuance is preserved.
- Assign the merged row's `impact`/`priority` once, over the merged finding (not
  once per source).
```

- [ ] **Step 3: Application-test dedup**

Dispatch a subagent with the new Summary Table + Deduplication sections and two row-summaries from different passes that describe the SAME issue at the same line (e.g. `PROP-06 | single-letter name o | ...` and `SCREAM-01 | generic name o | ...`, both at `queue.ts:2`), plus one unrelated finding.

Expected: the two same-line/same-fix findings collapse into ONE row whose `sources` column = `PROP-06, SCREAM-01`; the unrelated finding stays its own row with a single source ID. Total rows = 2.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/code-review-opinionated/SKILL.md
git commit -m "feat(code-review): dedup same-findings into one row with all source IDs"
```

---

## Task 3: Overlap log — the logging contract

**Files:**
- Modify: `.claude/skills/code-review-opinionated/SKILL.md` (add an Overlap Log section after Deduplication)

- [ ] **Step 1: Add the Overlap Log section**

Insert after the "## Deduplication" section, before "## State Tracking":

````markdown
## Overlap Log

After deduplication, append one entry per review to `docs/reviews/_overlap-log.md`
(create the file on first collision). This records facts already computed during
dedup; it requires no extra analysis.

**A `pass:concern` participant** is `<pass-name>:<concern>`. For passes that
declare `concerns:` frontmatter, use the finding's `concern`. For catch-all passes
with no `concerns:` (e.g. `general-review`), use the pass name as the concern, so
the participant is `general-review:general-review`.

**Entry format:**

```
## <YYYY-MM-DD> | <slug> | scope <BASE>..<HEAD> | passes: [<selected pass names>]
collisions_total_running: <N>

### Collisions (count + merged summary IDs)
- <passA:concernX> × <passB:concernY> [× <passC:concernZ> ...] — <count>  [<merged summary IDs>]

### Unmatched (counts only)
- <pass:concern> — <count>
```

**Logging rules (LOAD-BEARING — do not simplify):**

- **Each merge group is logged as ONE tuple carrying its FULL participant set**
  (every `pass:concern` in the merge), never decomposed into pairwise pairs. This
  is what makes count-only logging reconstructible — see `overlap-analysis.md` for
  the proof. Pairwise logging would break it.
- **Collisions:** group merge tuples by their identical full participant set;
  store a `count` (how many merges had that exact participant set) and the list of
  the merged rows' summary IDs.
- **Unmatched:** every finding NOT in any merge group, counted per `pass:concern`.
  Counts only — the findings themselves live in that review's `summary.md`.
- **`collisions_total_running`:** a running counter across ALL reviews. On each
  review, read the previous value from the last log entry (0 if the file is new),
  add this review's total collision count (sum of collision tuple counts), write
  the new total. This drives the auto-offer (see Overlap Nudges).
````

- [ ] **Step 2: Application-test the log entry**

Dispatch a subagent with the Deduplication + Overlap Log sections and a fixture: three passes selected (`general-review`, `code-properties`, `screaming-architecture`); a merge group of `code-properties:honest-names` + `screaming-architecture:vocabulary-audit` at one line; a merge of `general-review:general-review` + `code-properties:resilient` at another; and 4 unmatched general-review, 5 unmatched code-properties:correct, 1 unmatched screaming-architecture:stranger-reconstruction. Previous `collisions_total_running` = 45.

Expected: a well-formed entry; each collision is a single full-participant tuple (not split pairwise); collision tuples carry counts + merged IDs; unmatched are counts only; `collisions_total_running: 47` (45 + 2).

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/code-review-opinionated/SKILL.md
git commit -m "feat(code-review): append per-review overlap log (logging contract)"
```

---

## Task 4: Overlap nudges — per-review footer + auto-offer trigger

**Files:**
- Modify: `.claude/skills/code-review-opinionated/SKILL.md` (add an Overlap Nudges section after Overlap Log)

- [ ] **Step 1: Add the Overlap Nudges section**

Insert after the "## Overlap Log" section:

````markdown
## Overlap Nudges

**Per-review footer.** When a review had ≥1 collision, append to the bottom of
`summary.md` (before the end marker) a factual footer showing collision count,
unique counts per pass, and the top-3 colliding concern tuples with `+N more`
overflow:

```
Overlap this review: <C> collisions · unique — <pass>: <n>, <pass>: <n>, ...
Top colliding concerns: <concernX×concernY> (<count>), <...> (<count>)[, +<N> more]
```

**Auto-offer trigger.** When `collisions_total_running` crosses **100** (fixed;
not configurable), append an offer to that review's `summary.md` footer showing the
top-3 heaviest tuples + `+N more`:

```
100+ collisions logged. Heaviest overlaps: <X×Y> (<count>), <...> (<count>), +<N> more pairs.
Run overlap analysis? [now / remind next time / remind later]  (or ask "analyze pass overlap" anytime)
```

Offer responses:
- **now** — load `overlap-analysis.md` and run the decision-time analysis.
- **remind next time** — keep the counter unchanged (re-offers next review with
  collisions).
- **remind later** — reset `collisions_total_running` to 0 in the log (snooze a
  full cycle).
````

- [ ] **Step 2: Application-test both nudges**

(a) Footer: subagent with this section + a review that had 2 collisions and unique counts {general-review: 4, code-properties: 5, screaming-architecture: 1}, top tuples honest-names×vocabulary-audit (2), resilient×correct (1). Expected: a two-line footer matching the format; top tuples capped at 3 with `+N more` only if >3 tuples exist.

(b) Auto-offer: subagent told `collisions_total_running` just reached 103 (crossed 100). Expected: it appends the offer block with `[now / remind next time / remind later]` and the heaviest tuples; it does NOT auto-run analysis.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/code-review-opinionated/SKILL.md
git commit -m "feat(code-review): overlap nudges (per-review footer + 100-collision auto-offer)"
```

---

## Task 5: Create `overlap-analysis.md` (decision-time reference)

**Files:**
- Create: `.claude/skills/code-review-opinionated/overlap-analysis.md`

- [ ] **Step 1: Write the file**

Create `.claude/skills/code-review-opinionated/overlap-analysis.md` with this content:

````markdown
# Overlap Analysis (decision-time)

Loaded only when triggered — by the user answering "now" to the auto-offer, or
asking "analyze pass overlap" anytime. This is the rare, human-driven step that
turns the accumulated `docs/reviews/_overlap-log.md` into pass-responsibility
decisions. **The agent presents candidates and evidence; the user decides. The
agent never edits a pass on its own** (the skill's autonomy gates apply).

## Set model

For a concept R that passes A and B both touch, each review partitions R-findings
into **A∩B** (both caught), **A\B** (only A), **B\A** (only B).

- **Overlap** = size of A∩B → handled at runtime by dedup.
- **Directional subsumption (safe one-sided removal):** if across N reviews
  **A\B(R) is empty while B\A(R) is non-empty**, B subsumes A on R → removing R
  from A is licensed. Only the *removed* side's unique set must be empty; mutual
  equivalence is not required.

## Reconstructibility (why count-only logging suffices)

Counts per full-participant tuple plus unmatched counts recover the sets by
arithmetic across tuples. For passes A, B and concerns x, y:

- `total(A:x) = unmatched(A:x) + Σ counts of every tuple containing A:x`
- `A∩B on (x,y) = Σ counts of tuples containing BOTH A:x and B:y`
- `A\B = total(A:x) − Σ_y (A∩B on (x,y))`   (symmetrically for B\A)

A finding where A collides with a third pass C but not B sits in tuple
`{A:x, C:z}`: counted in `total(A:x)` but in no tuple containing a `B:*`
participant, so it lands correctly in `A\B`. This is **why each merge must be
logged as one full-participant-set tuple** — pairwise-decomposed logging breaks the
third term.

## Procedure

1. Read `docs/reviews/_overlap-log.md` (all entries).
2. **Cluster** the stable `pass:concern` labels into cross-pass concepts. This is
   the human judgment; the label set is small and stable, so it is tractable.
   Catch-all `pass:passname` participants do not cluster into shared concepts
   (their "concern" is just the pass name) — so catch-all passes are structurally
   excluded from removal.
3. Per concept R, compute the tallies (formulas above) across the logged reviews;
   assess directional subsumption and the sizes of each unique set.
4. Recommend exactly one of the **four moves**, with evidence, for the user to
   accept or reject:
   - **dedup-only** — overlap exists but both passes contribute unique findings;
     change nothing.
   - **remove-one-side** — directional subsumption holds; drop concept R from the
     subsumed pass.
   - **sharpen** — both have non-empty unique sets but collide on a shared
     sub-part; tighten each pass's R-instruction so they stop colliding while
     keeping distinct angles.
   - **split** — R deserves its own pass.

## Caveats to surface to the user

- **Longitudinal:** subsumption is a claim across many reviews; one review proves
  nothing. Report findings as "A\B(R) empty across last N reviews of R" and let the
  user judge whether N is enough.
- **B\A is ambiguous:** "B covers it and A doesn't" (clean boundary) vs "A covers
  it too but missed it this run" (recall failure) look identical in the data. Only
  the user reading the findings can tell them apart — surface the ambiguity, do not
  resolve it.
- **Absence of A\B is not proof:** finite codebase sample; A's unique value may
  live in code not yet reviewed. "Safe" is never proven.
````

- [ ] **Step 2: Application-test the analysis**

Dispatch a subagent with `overlap-analysis.md` and a synthetic `_overlap-log.md` containing ~4 entries engineered so that, for concept "naming" (code-properties:honest-names vs screaming-architecture:vocabulary-audit), honest-names has zero unmatched across all entries while vocabulary-audit has several. Ask it to run the procedure.

Expected: it computes that `honest-names \ vocabulary-audit` ≈ empty and `vocabulary-audit \ honest-names` non-empty, concludes directional subsumption (vocabulary-audit subsumes honest-names on naming), recommends **remove-one-side** (drop honest-names) — AND surfaces the longitudinal/ambiguity caveats and that it will not edit the pass itself.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/code-review-opinionated/overlap-analysis.md
git commit -m "feat(code-review): add overlap-analysis decision-time reference"
```

---

## Task 6: Wire the manual trigger + pointer into SKILL.md

**Files:**
- Modify: `.claude/skills/code-review-opinionated/SKILL.md` (Overlap Nudges section — add manual trigger + pointer)

- [ ] **Step 1: Add the manual trigger + pointer**

Append to the end of the "## Overlap Nudges" section:

```markdown
**Manual trigger.** "analyze pass overlap" runs the decision-time analysis at any
time, regardless of the counter. Load `overlap-analysis.md` and follow it.

The every-run knowledge (dedup, the logging contract, these nudges) lives here in
SKILL.md. The rare decision-time analysis (clustering, subsumption math, the four
moves) lives in `overlap-analysis.md` and is loaded only when triggered, to keep
this file lean.
```

- [ ] **Step 2: Verify the pointer resolves**

Run: `ls .claude/skills/code-review-opinionated/overlap-analysis.md`
Expected: the file exists (created in Task 5).

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/code-review-opinionated/SKILL.md
git commit -m "feat(code-review): wire manual overlap-analysis trigger + pointer"
```

---

## Task 7: End-to-end application test

**Files:** none modified — verification only.

- [ ] **Step 1: Build a fixture repo**

Create a throwaway git repo under `/tmp/cr-overlap` with a base commit and a feature branch whose diff contains at least: one issue catchable by two passes at the same line/same-fix (for a collision), and issues unique to single passes (for unmatched).

- [ ] **Step 2: Run two passes against the fixture and have the orchestrator integrate**

Dispatch pass subagents (`code-properties`, `screaming-architecture`) per their files, then dispatch the orchestrator with the full updated SKILL.md to: dedup, write `summary.md` (with `sources` column), and append to `_overlap-log.md`.

Expected:
- `summary.md` has a `sources` column; the same-line/same-fix issue is ONE row with two source IDs.
- `_overlap-log.md` exists with one entry: a single full-participant collision tuple (count + merged IDs), unmatched counts, and a correct `collisions_total_running`.
- A per-review footer is present.
- No file outside `docs/reviews/` was created or modified (autonomy gates held).

- [ ] **Step 3: Clean up**

```bash
rm -rf /tmp/cr-overlap
```

- [ ] **Step 4: Update the SKILL.md Passes note if needed and final commit**

If any wording drifted during testing, fix inline. Then:

```bash
git add -A
git commit -m "test(code-review): verify end-to-end dedup + overlap log integration"
```

---

## Notes for the implementer

- **No executable tests exist** in this skill. "Application-test" = dispatch a
  subagent that has ONLY the written instruction + a fixture, then check its output
  artifact. This mirrors how the existing passes were verified.
- **Autonomy gates are sacred:** every subagent test must confirm nothing was
  written outside `docs/reviews/`. If a test subagent edits code, the instruction
  failed — fix the instruction, do not loosen the gate.
- **Load-bearing rule:** the full-participant-set tuple logging (Task 3) is what
  makes the math (Task 5) valid. Do not let either drift from the other.
