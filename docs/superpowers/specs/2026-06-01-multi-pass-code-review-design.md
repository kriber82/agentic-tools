# Multi-Pass Code Review Skill — Design

**Date:** 2026-06-01
**Skill name:** `code-review-opinionated`
**Type:** Technique skill with a discipline-enforcing core (autonomy gates)

## Problem

A code review is run as several independent passes (security, performance, naming/consistency,
etc.). The prior workflow ran each pass as a prompt that wrote its findings to a separate file,
then a further prompt integrated those files into a summary. This worked well for two reasons
worth preserving:

1. **Provenance** — you could see which pass found each finding.
2. **Integrated ranking** — a single table ranked all findings by a common score, even though
   each pass ranks by its own native metric.

But the loose pile of per-pass files plus a hand-maintained summary was a headache: information
duplicated across files, cross-references to keep in sync, no clean state tracking, and no clear
way to resume an interrupted run.

## Goals

- One coordinated set of files with a clear contract, no duplicated/ drifting information.
- Keep provenance (which pass found each finding).
- Keep one integrated, ranked table across all passes.
- Add durable **state tracking** for working through findings.
- Support **parallel** pass execution.
- Be **resumable** after interruption.
- Fold in the user's existing pass prompts, made composable and discoverable.

## Non-Goals

- No tie to the product / feature-review workflow. Fully independent.
- The skill defines coordination + the file contract; pass prompts define *what to look for*.
- The agent does **not** fix findings as part of review (see Autonomy Gates).

## Architecture

### Workflow

1. **Scope.** Determine the review scope as the diff since the branch point (where the current
   branch diverged from its base). If there is no branch / no detectable divergence point, the
   skill **asks the user** which commit/ref to review from. Never guesses.
2. **Discover passes.** Orchestrator globs `passes/*.md`, reads each one's frontmatter, and
   presents them to the user as a selectable list. User chooses which to run.
3. **Run passes in parallel.** Each selected pass runs as its own subagent against the scoped
   diff/codebase.
4. **Each pass writes one detail file** (`<output-dir>/<pass>.md`), its source of truth, ending
   with a completion marker.
5. **Each pass returns a compact row-summary** to the orchestrator (ephemeral — not persisted;
   regenerable from the detail file headers).
6. **Orchestrator writes the summary file** in phases (see below): the one integrated, ranked,
   state-tracked table.
7. **Resume:** on re-entry, scan the output dir and run only missing/incomplete passes, then run
   the orchestrator.

### Output location

`docs/reviews/<slug>/`

- `slug` is **user-definable**; the skill **proposes a slug derived from the branch name**.
- `<pass>.md` — one detail file per pass (source of truth for that pass's findings).
- `summary.md` — the single integrated table + state tracking.

(No stub files for skipped passes — skipped passes are recorded in the summary header instead, to
honor the no-clutter goal.)

### Finding entry (in each detail file)

Each finding has:

- **ID** — `<PASS>-NN` (e.g. `SEC-03`), stable, referenced by the summary.
- **Per-finding metadata header** (machine-readable):
  - `confidence` — the pass's own confidence the finding is real. (Pass knows this best.)
  - `effort` — the pass's estimate of fix effort, *if it has a sense of it*; else omitted /
    neutral.
  - `native_score` + `native_metric` — the pass's own ranking value and what metric it used
    (provenance).
  - `impact-evidence` — a short note grounding impact ("affects one log line" vs "unbounded memory
    growth on hot path").
- **Prose body** — file references, the proposed change/refactor, and the explanation.
- A **completion marker** at the end of the file (text sentinel).

Note: passes do **not** emit the cross-pass impact number or the final priority — see Scoring.

### Scoring — split responsibility

Each pass is blind to the others, so it cannot calibrate impact to a global scale, and there is a
known failure mode where a low-yield pass inflates the impact of minor findings to look valuable
("scale inflation under isolated self-assessment"). Therefore:

- **Passes emit raw local signal:** `confidence`, `effort` (if known), `native_score` /
  `native_metric`, and an `impact-evidence` note. They state impact only in their **native terms**.
- **Orchestrator assigns the common `impact`** by reading every finding's native score + impact-evidence
  with all findings in view, mapping impact onto the shared scale, re-grounding any inflated
  claims against the full set.
- **Common score:** `priority = impact × confidence ÷ effort`. This is derived from the
  established **RICE** prioritization model (Reach × Impact × Confidence ÷ Effort), dropping
  *Reach* — a product/user metric that does not map cleanly onto code-review findings. Anchoring
  to RICE keeps the metric grounded rather than arbitrary. When effort is unknown, `effort = 1`
  (no division). Written by the orchestrator.
- `native_score` is retained in the summary as a provenance column.

### Summary file

Written by the orchestrator in **phases**, so partial writes are legible:

1. **Header first:** which passes were *requested*, which were *skipped*, and the review scope
   (branch point or chosen ref).
2. **Wait** for the passes to finish.
3. **Fill the table.**
4. **Write the summary's own completion marker** last.

On re-run, the orchestrator can detect its own partial write via the missing end marker.

**Table columns:**
`priority` (sort key) · `id` · `pass` (provenance) · `title` · `impact` · `confidence` ·
`effort` · `native_score` · `status` · `rationale`

ID references point back into the detail files.

### State tracking

- `status` lives **only** in the summary table (single source of truth).
- Status vocabulary (experimental, expected to evolve):
  `OPEN` (default) · `THIS_BRANCH` (accepted into the branch under review) · `DEFERRED` (to a
  later improvements pass) · `FIXED` · `WONTFIX`.
- A one-phrase `rationale` field accompanies status, **required for `WONTFIX`** ("low value vs
  effort", "intentional", "pre-existing", "false positive"). We deliberately do **not** add a
  separate "not enough value" status — that is already expressed by a low `priority`; the
  rationale note carries the reason without multiplying statuses.
- On orchestrator **re-run, status (and rationale) is merged, never overwritten** — the table is
  otherwise regenerable, but user-entered status is not.

### Triage (branch-vs-defer) — optional, default-on

A tool to manage the current high volume of review findings; expected to fade as reviews get
cleaner.

- If the user doesn't state a preference, the skill **does** triage **unless** there are only a
  few findings, in which case it **proposes skipping** the `THIS_BRANCH` / `DEFERRED` split.
- The orchestrator **proposes** a classification per finding with a one-line rationale, but **the
  user makes the call.** The agent presents; the user dispositions.

### Autonomy Gates (discipline-enforcing — hard rules)

Two distinct temptations, two explicit rules:

1. **Triage gate:** the agent **does not assign final triage status on its own.** It proposes
   `THIS_BRANCH` / `DEFERRED` with rationale; the user decides.
2. **Execution gate:** the agent **never modifies code to address a finding** unless the user
   explicitly asks, naming the finding(s). Producing the review is the deliverable; fixing is a
   separate, explicitly-prompted action.
3. **Workflow-handoff gate:** even when the user *does* ask the agent to act on findings, the
   agent **does not immediately start editing.** It first **proposes routing the fix through the
   user's normal workflow** (superpowers / another spec-driven tool / deliberately vanilla) and
   waits for the user to choose. This targets a distinct, observed failure mode: on "let's go fix
   that," agents drop into ad-hoc fixing and *both* the agent and the user forget to use the
   normal spec-driven process. The instruction "let's go fix that" is therefore a **trigger for
   the handoff prompt**, not a license to start editing.

These get a red-flags list and a rationalization table in the skill (e.g. "the fix is trivial so
I'll just do it" → no; "but the user clearly said fix it, so process is overhead" → no, propose
the workflow handoff first), and will be pressure-tested against subagents during skill testing.

### Resume logic

The detail files are the progress ledger; no separate state file.

- detail file present **with** completion marker → pass done, skip.
- detail file absent, or present **without** marker → not done, (re-)run it.
- all detail files complete, no `summary.md` (or `summary.md` without its end marker) → run /
  finish the orchestrator.

## Passes (folded in, discoverable, composable)

- Shipped as `passes/*.md`, discovered by glob (drop a new file in → it appears as an option).
- Each pass file has **frontmatter**: `name`, one-line `description`, and `estimates_effort`
  (bool). Same shape for all → composable.
- Each pass body ends by instructing the subagent to write its detail file in the standard
  finding-entry schema (IDs, metadata header, impact-evidence, completion marker) and to return the
  compact row-summary.
- The user's existing pass prompts will be folded in and refactored to this shape, preserving
  their wording and intent while normalizing the output contract.

## Skill structure (for the build phase)

```
.claude/skills/code-review-opinionated/
  SKILL.md                 # overview, workflow, file contract, scoring, gates, resume
  passes/
    <pass-name>.md         # one per review pass (frontmatter + body + output contract)
  templates/               # (if needed) finding-entry + summary-table templates
```

## Open items to resolve during build

- Collect the user's existing pass prompts to fold in.
- Exact wording of completion-marker sentinels.
- Whether a finding-entry / summary-table template warrants its own file vs inline in SKILL.md.
