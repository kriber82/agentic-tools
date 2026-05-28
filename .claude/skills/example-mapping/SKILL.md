---
name: example-mapping
description: Use when a user story or feature needs to be elaborated before writing acceptance tests or implementation — surfaces rules, concrete examples, and open questions through structured facilitation
---

# Example Mapping

## Overview

Example Mapping is a structured pre-development conversation technique. It surfaces business rules, concrete examples, and open questions using four card types — preventing scope creep, hidden assumptions, and thin acceptance criteria.

**Core principle:** Surface ambiguity as explicit question cards rather than resolving it inline. A session with 8 well-formed questions is more valuable than one with 0 questions and hidden assumptions.

**Supporting files — load when indicated:**
- `methodology.md` — card types, facilitation loop, board format, output format
- `role-perspectives.md` — four-lens question bank (Business, Test, UX, Dev)

## Workflow

### Orient
**Load `methodology.md` NOW before proceeding.**

1. Read `CLAUDE.md` and any project context files to ground domain vocabulary and persona names
2. Ask: what story or feature are we mapping? (one sentence)
3. Ask: who is the primary user? (check if a persona already exists in project context)
4. Confirm what is explicitly OUT of scope for this session

Gate: story named | persona identified | scope boundaries set

### Facilitate
**Load `role-perspectives.md` NOW before proceeding.**

The user drives discovery. Ask questions and render the board — do not generate cards on the user's behalf unless prior brainstorm context is rich enough to extract from (see Phase 1 authorship rules in `methodology.md`).

Run the **two-phase mapping process** defined in `methodology.md` § Session Structure:

1. **Name the story** (yellow card) — one sentence, user perspective.
2. **Phase 1 (Skeleton)** — enumerate the rule categories the story touches (Business is always 1.a). Iterate sub-passes 1.a, 1.b, 1.c… each producing rule titles + 1-line **principle** example bullets + question stubs. End with the structural sanity check (failure coverage, B/V boundary, rule purity).
3. **Phase 2 (Promotion)** — for each category in turn:
   - 2.a Business → bullets to full form with concrete examples → scoped lens (Business + Test + BDD)
   - 2.b Visualization → UI draft pass + short-form V-rule iteration → full-form V-rules with concrete examples → scoped lens (UX + Test + BDD + Dev)
   - 2.c Other → full-form rules with concrete examples → scoped lens (Test + Dev + relevant)
4. **Final full lens pass** across the whole map (all five lenses) + closing retro question on lens-pass value.
5. **Quorum gate** (see `methodology.md`), then ask: *"Anything else before producing the output document?"* — never declare the session over.

Gate: user confirms done | UI draft settled | per-category lens passes complete | final full pass complete | quorum checked | gaps flagged | user approves output

### Produce Output
Save to `docs/stories/NNNNN-<slug>/example-map.md` (see `docs/project-conventions.md` for story folder naming).

Full output format is defined in `methodology.md`: story | rules + examples (with bold-prefix headlines) | open questions | rendering reference (for UI features) | handoff package.

Gate: document written | user reviews and approves

## Critical Rules

- Every rule needs at least one happy path **Phase 2** example before producing output — non-negotiable
- Non-trivial rules without edge/failure coverage are **flagged as gaps** in the output, not session blockers
- If 3+ High-priority red cards remain unresolved at session end: mark `Ready for handoff: No`
- Phase 2 examples use real names and real data — Phase 1 principle bullets may use category nouns ("empty inventory")
- Question cards are output, not failure — do not resolve ambiguity inline. Only **mechanical** resolutions (unambiguous referenced source) promote to RESOLVED inline; everything else is `Unresolved — lean: X` until user confirms.
- If a resolved question implies a new rule, always ask: *"Does this answer imply a rule we should add?"*
- Each rule covers exactly one concern. When a split into single-concern parts isn't straightforward, surface the options to the user with a recommendation rather than picking unilaterally.
