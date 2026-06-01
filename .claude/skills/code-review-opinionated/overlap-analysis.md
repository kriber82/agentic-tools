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
