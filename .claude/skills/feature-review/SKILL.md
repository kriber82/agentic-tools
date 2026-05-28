---
name: feature-review
description: Use after a feature's manual testing session to work through findings, apply process improvements, and close the feature with all items accounted for
---

# Feature Review Workflow

## Overview

Closes a feature by working through all findings until every item is accounted for. **Process improvements always come before artifact changes** — improved tools govern the work that follows.

## Phase 1: Gather Findings

1. Read `docs/stories/NNNNN-<slug>/retro.md` — collect all items with status `OPEN`, `OPEN-FIX_NOW`, or `?`
2. Ask the user: any additional findings not yet captured?
3. Triage each finding into two dimensions:

   **Scope** (determines whether PO go-ahead is required before fixing):
   - **Implementation-scope** — fixes what was already agreed upon: bugs, regressions, code quality issues, missing tests for agreed behaviour. Proceed without asking.
   - **Feature-scope** — changes what the product does: new behaviour, additional data sources, changed outputs, updated acceptance criteria. Requires a plan and explicit PO approval before any implementation.

   **Change category** (determines fix order):
   - **Process** — implies a change to a skill, convention, or process document
   - **Example map** — implies a change to `example-map.md`
   - **Feature file** — implies a change to a `.feature` file
   - **Tests** — implies a change to unit or acceptance tests
   - **Prod** — implies a change to production code

A finding may touch multiple categories — note all of them; the upstream-first rule governs execution order.

## Phase 2: Apply Process Improvements First

For every finding with a process dimension:
1. Apply the change to the relevant skill or convention file **now**, before touching any feature artifact
2. After applying: check whether this improvement is **testable via fresh session** — i.e. would a review agent running the improved process catch this finding without being told about it in advance? If yes, flag it to the user:

   > "This process improvement is testable. I can run the affected review step in a clean session — without referencing the known finding — to see if the improved process catches it on its own. Want to try it?"

Gate: all process improvements are either applied or explicitly deferred before proceeding to Phase 3.

## Phase 2.5: Feature-Scope Gate

Before implementing any artifact fix, identify all feature-scope findings.

For each feature-scope finding:
1. Draft a brief plan:
   - What change is proposed?
   - Which artifact is furthest upstream (example map, feature file, tests, prod)?
   - What is the full propagation chain from there?
2. Present the plan to the PO and ask for explicit go-ahead before proceeding.

Do not implement any feature-scope fix until the PO has approved the plan for that finding. Implementation-scope findings may proceed without this step.

## Phase 3: Fix Artifacts Upstream-First

Sort remaining findings by their furthest-upstream change category:

```
example-map.md → .feature files → tests → prod code
```

Start with the highest upstream finding. Work downward — each artifact is driven by what the artifact above it now says.

**Subset approach:** if some findings are not yet actionable (blocked on a higher-level decision or another finding), work the actionable subset first. Return to blocked items after each pass — upstream fixes often unlock downstream clarity.

Never fix a downstream artifact to match the current state of an upstream one that itself needs changing. Fix upstream first, then let the correction propagate.

## Phase 4: Iterate

After completing a pass:
- Did fixing upstream items surface new findings or reveal new process insights?
- Are any previously blocked findings now actionable?
- Did the work create new OPEN items?

If yes to any: return to Phase 2 (if process insights emerged) or Phase 3 (if artifact changes only). Repeat until a full pass produces no new actionable items.

## Phase 5: Gate Before Close

Every finding must reach a terminal status before the feature is declared done:

| Status | Meaning |
|--------|---------|
| `FIXED` / `AGENT_FIXED` | Resolved this cycle |
| `BACKLOG` | Deliberately deferred — item transferred to `docs/product-backlog.md` or `docs/process-backlog.md` |
| `WONTFIX` | Accepted as-is — rationale recorded in retro |

Both immediate fixes and process improvements are subject to this gate. `BACKLOG` and `WONTFIX` are valid outcomes; an item with no terminal status is not done — it is lost.

## Phase 6: Write the Agent Log

At the end of the session, append to `docs/stories/NNNNN-<slug>/agent-catches-log.md` any finding the agent detected and acted on autonomously (not explicitly requested by the user):

```
YYYY-MM-DD | [finding summary] | [action taken]
```

This is the agent's record of its own work — distinct from the retro, which is the PO's finding log.
