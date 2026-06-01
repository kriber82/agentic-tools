---
name: code-review-opinionated
description: Use when running a multi-pass code review on a branch or diff and you need provenance (which pass found what), a single ranked findings table, durable state tracking across one set of files, and resumability after interruption. Also use when about to act on review findings — editing code, committing, merging, or triaging which findings ship — to enforce that the user, not the agent, makes those calls.
---

# Multi-Pass Code Review

## Overview

Run several independent review passes over a branch/diff, each writing its own detail file, then have one orchestrator build a single ranked, state-tracked summary table. Provenance is preserved (every finding names its pass), findings are ranked by a common score across passes, and the whole run is resumable.

**The deliverable of a review is the findings — not fixes.** Producing the review never includes changing the code. See Autonomy Gates; they are not optional.

## When to Use

- You review a branch/diff with multiple lenses (security, performance, naming, etc.) and want one integrated result instead of a pile of separate files.
- You need to see which pass found each finding, and rank everything on one scale.
- You want durable status tracking while working through findings, and the ability to resume an interrupted review.

Not for: single-lens quick reviews where one pass and a chat reply suffice; product/feature-scope review (that is a separate workflow).

## Workflow

```dot
digraph review {
    "Determine scope" [shape=box];
    "Branch point detectable?" [shape=diamond];
    "Ask user for review ref" [shape=box];
    "Discover passes/*.md" [shape=box];
    "User selects passes" [shape=box];
    "Orchestrator writes summary HEADER\n(requested + skipped + scope)" [shape=box];
    "Run selected passes in parallel" [shape=box];
    "Each pass writes <pass>.md + end marker" [shape=box];
    "Orchestrator fills table, assigns impact+priority" [shape=box];
    "Orchestrator writes summary END marker" [shape=box];

    "Determine scope" -> "Branch point detectable?";
    "Branch point detectable?" -> "Ask user for review ref" [label="no"];
    "Branch point detectable?" -> "Discover passes/*.md" [label="yes"];
    "Ask user for review ref" -> "Discover passes/*.md";
    "Discover passes/*.md" -> "User selects passes";
    "User selects passes" -> "Orchestrator writes summary HEADER\n(requested + skipped + scope)";
    "Orchestrator writes summary HEADER\n(requested + skipped + scope)" -> "Run selected passes in parallel";
    "Run selected passes in parallel" -> "Each pass writes <pass>.md + end marker";
    "Each pass writes <pass>.md + end marker" -> "Orchestrator fills table, assigns impact+priority";
    "Orchestrator fills table, assigns impact+priority" -> "Orchestrator writes summary END marker";
}
```

1. **Scope.** Review the diff since the branch point (where the current branch diverged from its base). If there is no branch or no detectable divergence point, **ask the user** which commit/ref to review from. Never guess the scope.
2. **Discover passes.** Glob `passes/*.md` (in this skill dir), read each one's frontmatter, present them as a selectable list. The user chooses which to run.
3. **Header first.** Before launching passes, write `docs/reviews/<slug>/summary.md` with a header recording: which passes were *requested*, which were *skipped*, and the review scope (ref/branch point). This makes a partial run legible.
4. **Run passes in parallel**, each as its own subagent against the scoped diff.
5. **Each pass writes one detail file** `<pass>.md`, ending with its completion marker, and returns a compact row-summary (ephemeral — regenerable from the detail file headers; do not persist it separately).
6. **Orchestrator fills the table** (see Scoring), then writes the summary's own end marker last.

## Output Location

`docs/reviews/<slug>/`

- `slug` is user-definable; **propose one derived from the branch name** and let the user override.
- `<pass>.md` — one detail file per pass; the source of truth for that pass's findings.
- `summary.md` — the single integrated table + state tracking.

No stub files for skipped passes — record skipped passes in the summary header instead.

## Finding Entry (in each detail file)

Each finding:

- **ID** — `<PREFIX>-NN` (e.g. `SEC-03`), where `<PREFIX>` is the pass's `id_prefix` frontmatter value; stable, referenced by the summary.
- **Metadata header** (machine-readable):
  - `confidence` — the pass's confidence the finding is real (the pass knows this best).
  - `effort` — fix-effort estimate, *only if the pass has a sense of it*; else omit.
  - `native_score` + `native_metric` — the pass's own ranking value and what metric produced it (provenance).
  - `impact-evidence` — a short note grounding impact ("affects one log line" vs "unbounded memory growth on hot path").
- **Prose body** — file references, the proposed change/refactor, the explanation.
- **Completion marker** as the last line: `<!-- end:<pass> -->`.

Passes do **not** emit the cross-pass impact number or the final priority — see Scoring.

## Scoring — Split Responsibility

Each pass is blind to the others, so it cannot calibrate impact to a global scale. There is a known failure mode: a low-yield pass inflates the impact of minor findings to look valuable ("scale inflation under isolated self-assessment"). Therefore:

- **Passes emit raw local signal:** `confidence`, `effort` (if known), `native_score`/`native_metric`, and `impact-evidence`. They state impact only in native terms.
- **The orchestrator assigns the common `impact`**, with all findings in view, re-grounding inflated claims against the full set.
- **Common score:** `priority = impact × confidence ÷ effort`. Derived from the **RICE** model (Reach × Impact × Confidence ÷ Effort), dropping *Reach* (a product metric that doesn't map to code findings); anchoring to RICE keeps the metric grounded. When effort is unknown, `effort = 1`.
- `native_score` is kept in the summary as a provenance column.

## Summary Table

Columns:

`priority` (sort key) · `id` · `pass` · `title` · `impact` · `confidence` · `effort` · `native_score` · `status` · `rationale`

IDs reference back into the detail files. Write the table sorted by `priority` descending.

## State Tracking

- `status` lives **only** in the summary table — single source of truth.
- Vocabulary: `OPEN` (default) · `THIS_BRANCH` (accepted into the branch under review) · `DEFERRED` (to a later improvements pass) · `FIXED` · `WONTFIX`.
- `rationale` is a one-phrase note accompanying status, **required for `WONTFIX`** ("low value vs effort", "intentional", "pre-existing", "false positive"). Do not add a separate "not enough value" status — low value is already expressed by a low `priority`.
- On orchestrator **re-run, merge status and rationale — never overwrite** them. The rest of the table is regenerable; user-entered status is not.

## Triage (branch-vs-defer) — optional, default-on

A tool to manage high finding volume; expected to fade as reviews get cleaner.

- If the user states no preference, **do** triage — **unless** there are only a few findings, in which case **propose skipping** the THIS_BRANCH/DEFERRED split.
- **Propose** a classification per finding with a one-line rationale. **The user makes the call.** You present; the user dispositions. (See Triage gate.)

## Resume

The detail files are the progress ledger — there is no separate state file.

- detail file present **with** `<!-- end:<pass> -->` → pass done, skip it.
- detail file absent, or present **without** its end marker → not done, (re-)run it.
- all selected detail files complete, but `summary.md` missing its end marker → finish the orchestrator step.

On re-entry: scan `docs/reviews/<slug>/`, run only missing/incomplete passes, then run the orchestrator (merging any user-entered status).

## Autonomy Gates — HARD RULES

The baseline failure this skill prevents: given a review and a nudge ("merge when I'm back", "let's go fix the top 3"), agents edit the code, commit, and merge — collapsing review into unrequested implementation. These gates are not advisory.

**Violating the letter of these gates is violating their spirit.**

### Gate 1 — Execution (positional, absolute)

During a review, you write **only** to the review output directory `docs/reviews/<slug>/`.

You do **not** edit, create, stage, commit, or merge **any** file outside that directory — no production code, no tests, no config — regardless of how small, obvious, or explicitly requested the change is.

If the user wants a change made, **point to the exact file and line, or paste the snippet, for the user to apply.** You do not apply it. You never run `git commit` or `git merge` — those are always the user's action.

### Gate 2 — Triage

You do **not** assign final triage status (THIS_BRANCH / DEFERRED) on your own. You **propose** dispositions with rationale; the user decides. "Sort out what ships vs defers" means *produce a proposal*, not *finalize and act*.

### Gate 3 — Workflow-handoff

When the user later asks you to act on findings ("let's go fix the top 3"), this is a **trigger to propose a process, not to start editing.** Before any implementation, propose routing the work through the user's normal workflow (superpowers / another spec-driven tool / deliberately vanilla) and wait for them to choose. Implementing fixes is separate, explicitly-prompted work that happens *outside* the review — and even then it is started by the user picking a route, not by you editing.

## Red Flags — STOP

If you catch yourself thinking any of these during a review, stop:

- "The fix is trivial / one line, I'll just apply it."
- "They said merge when they're back, so I should make it mergeable."
- "They said 'let's go fix it,' so I'll start editing."
- "I'll stage the changes so they're ready for review." (Staging code is writing code.)
- "The split is obvious, I'll just assign THIS_BRANCH/DEFERRED myself."
- "I'll commit it for them to save time."
- "While I'm in this file I'll also fix the adjacent thing."

All of these mean: **write only under `docs/reviews/`, propose, and hand back to the user.**

## Rationalization Table

| Excuse | Reality |
|--------|---------|
| "It's a one-line fix, applying it is harmless." | The deliverable is the review. Point at the line; the user applies it in seconds. |
| "They said the branch needs to merge — that implies fixing." | "Merge when I'm back" is context, not a request to edit/commit/merge. You never commit or merge. |
| "They explicitly said 'fix the top 3,' so editing is authorized." | That triggers Gate 3 — propose a workflow and wait. It does not authorize editing during review. |
| "Staging isn't committing, so it's allowed." | Staging writes the change into the index. Gate 1 forbids writing outside `docs/reviews/`. |
| "The triage split is obvious; deciding it saves them time." | Deciding what ships is the user's call. Propose with rationale; let them disposition. |
| "Tests don't exist here, but the fix is obviously correct." | Unverifiable confidence is exactly why fixes route through a real workflow, not a review. |
| "While I'm here I'll clean up the adjacent code." | Make only what was asked, and only under `docs/reviews/`. No opportunistic edits. |

## Passes

Review passes live in `passes/*.md`, discovered by glob. Each has frontmatter (`name`, `description`, `id_prefix`, `estimates_effort`) and a body that ends by instructing the subagent to write its detail file in the Finding Entry schema (IDs use `id_prefix`, metadata header, impact-evidence, end marker) and return the compact row-summary. Drop a new file in `passes/` to add a pass; it appears as an option automatically.

Shipped passes:
- `general-review` — broad senior-engineer review; wraps `superpowers:requesting-code-review`.
- `screaming-architecture` — per-file intention-clarity review (Stranger/Substitution/Vocabulary tests); proposes code-only refactorings. Estimates effort.
- `code-properties` — checklist review against functional / locally-understandable / maintainability properties; names the violated property per finding. Partial overlap with the two above is intended.
