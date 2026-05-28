---
name: example-mapping-role-perspectives
description: Five-lens question bank for Example Mapping sessions — Business, Test, UX, Dev, and BDD perspectives applied per-category in Phase 2 plus a final full pass
---

# Role Perspectives — Five Lenses

Apply these five lenses according to the two-phase mapping process in `methodology.md`. Each lens scans the rules and examples within its scope (per-category or whole-map) for the issues it is most qualified to spot, then reports all findings — not just one question per lens, but all notable gaps it sees — with a priority level on each.

Present all lens findings for a given pass in a single response. The user reads the full report and decides what to act on. This is a compressed review pass, not an iterative dialogue.

## When to Apply

Lenses run at three points in Phase 2 (see Session Structure in `methodology.md`):

- **Per-category scoped passes** at the end of each Phase 2 sub-pass — only the lenses relevant to that category run, scoped to that category's rules:
  - 2.a Business → **Business + Test + BDD**
  - 2.b Visualization → **UX + Test + BDD + Dev** (after the UI draft is settled)
  - 2.c Other → **Test + Dev** + lenses relevant to the category
- **Final full pass** after all per-category sub-passes complete — all five lenses across the whole map. This catches cross-category issues (V→B reference integrity, cross-rule conflicts, persona consistency) and provides a final spec-quality check.

After the final full pass, ask one closing retro question: *"Was this final pass valuable, or too much after the per-category passes?"* Capture the answer in the story's retro to tune lens scoping over time.

### Mid-pass surfacing of HIGH-severity findings

Per-category lens passes run at the **end** of each Phase 2 sub-pass, but **🔴 HIGH-severity findings surface inline as soon as the facilitator notices them** — not held back for the end-of-pass batch.

- 🔴 HIGH: surface immediately. Revising a rule with a high-severity gap is cheaper before examples accumulate against the bad framing.
- 🟡 MED: surface mid-pass at the facilitator's discretion when it would materially change the rule under discussion; otherwise hold for the end-of-pass batch.
- 🟢 LOW: always wait for the end-of-pass batch.

Independence-proof flags (BDD lens, rule-atomicity detection — see below) are a common HIGH-severity surfacing target: catching a bundled rule before its examples accumulate saves rework that compounds with example count.

**Format:** One block per lens, findings listed with F-number + 🔴 HIGH / 🟡 MED / 🟢 LOW. Number sequentially across all lenses in a single pass (F1, F2, F3…). Close with a decision prompt.

> Here are the lens checks for this pass — tackle 🔴 HIGH items before closing; defer or skip 🟡 MED and 🟢 LOW at your discretion:
>
> **Business**
> F1 🔴 B2 assumes buy preference is global — no example covers per-recipe override
> F2 🟢 B1 boundary (max item count) is underdefined but low risk for current scope
>
> **Test**
> F3 🔴 B1 has no failure example for item-not-found
> F4 🟡 B4 boundary at quantity 0 is covered but the empty-input revert path has no example yet
>
> **BDD**
> F5 🔴 B3-2 contains "[×3 scaled]" — not a concrete value; surface as a red card or fill it in
>
> Which items do you want to address? (reference by F-number)

Skip any lens that has nothing to flag (omit the block entirely rather than writing "nothing to add").

Skip any lens whose scope is empty for the current pass (e.g. UX in a 2.a Business pass).

---

## Business Lens

**Focus:** Business rules, exceptions, and boundary conditions from a business/domain perspective.

**Core question types:**
- *"Is [rule] always true, or are there legitimate exceptions?"*
- *"What's the business cost of getting [rule] wrong?"*
- *"Who is the authority for [rule] — is there a domain expert who could override this?"*
- *"Does [rule] vary by context (user type, time, configuration)?"*

**Typical gaps found:**
- Implicit exceptions that "everyone knows" but aren't stated
- Rules that are actually policies (can be changed) masquerading as invariants
- Missing boundary conditions at the edges of a rule's validity
- Rules that conflict with each other under certain inputs

**Calibration:**
- If a rule looks clean and well-bounded: *"Thinking from a business perspective: is there any case where [rule] should NOT apply?"*
- If a rule looks incomplete: *"[Rule] seems to cover the normal case — what does the business allow when [specific edge]?"*

---

## Test Lens

**Focus:** Edge cases, failure modes, boundary conditions, and unhappy paths.

**Core question types:**
- *"What's the most likely way [rule] could break in practice?"*
- *"What happens at the extremes — zero items, maximum items, empty input?"*
- *"What if two rules apply simultaneously — which one wins?"*
- *"What does the system do when [rule]'s precondition isn't met?"*

**Typical gaps found:**
- Rules with only a happy path example and no failure coverage
- Boundary values not specified (what counts as "too many"? "too long"?)
- Concurrent or race conditions (two users, rapid clicks)
- Unhappy paths that degrade silently rather than visibly

**Calibration:**
- If a rule has good happy path coverage: *"Thinking as a tester: what's the most likely failure mode for [rule]?"*
- If a rule has an obvious gap: *"[Rule] has no failure example yet — what happens if [specific failure condition]?"*

---

## UX Lens

**Focus:** User perception, feedback clarity, rendering, and discoverability.

**Core question types:**
- *"What does the user see immediately after [rule]'s outcome occurs?"*
- *"How does the user know the action succeeded — or failed?"*
- *"Is the outcome of [rule] reversible from the user's perspective?"*
- *"What does the UI look like in the empty/zero state — before any interaction?"*

**Typical gaps found:**
- Rules that describe system behaviour but not user-visible feedback
- Missing rendering rules for conditional UI elements
- Loading/transition states not captured as rules
- Error states that are technically handled but visually silent

**Calibration:**
- If a rule describes an action with no visible outcome yet: *"Thinking as a UX designer: what does the user see after [action] — how do they know it worked?"*
- If a rendering rule exists but no template yet: *"Can you sketch what that section looks like? I'll capture the template."*

---

## Dev Lens

**Focus:** Technical constraints, async/loading states, integration edge cases, and feasibility flags.

**Core question types:**
- *"What does the UI show while [rule]'s data is being loaded or computed?"*
- *"What if the data for [rule] isn't available yet — stale, missing, or still fetching?"*
- *"Are there performance implications if [rule] is triggered with very large input?"*
- *"Does [rule] depend on any external system that could be unavailable?"*

**Typical gaps found:**
- Loading states not captured (rule assumes data is always ready)
- Error states for external dependencies (API down, file missing, network timeout)
- Performance edge cases not flagged as questions
- Implicit technical constraints that should be made explicit as rules or questions

**Calibration:**
- If a rule assumes synchronous data availability: *"Thinking as a developer: what does the UI show while the recipe tree is being resolved — is there a loading state we need to design?"*
- If a rule relies on external data: *"What happens to [rule] if the data source is unavailable?"*

---

## BDD Expert Lens

**Focus:** Specification quality — examples that are concrete, self-contained, free of implementation history, and correctly classified between domain (B) and visualization (V).

**Rules this lens enforces:**

1. **No implementation history** — examples state desired behaviour, not past behaviour. Any language that only makes sense given knowledge of a prior version ("unlike before", "on blur", "on commit", "the old approach") is describing history. Rewrite to the observable outcome.

2. **No placeholders in Phase 2** — every value in a Phase 2 example is concrete and testable now. Brackets, "TBD", "verify later", and stand-in formulas are deferred decisions that will never be made. Unknown values become red question cards. (Phase 1 principle bullets may use category nouns like "empty inventory" — placeholder rule applies after promotion.)

3. **Self-contained** — each Phase 2 example carries exactly the information needed to write an acceptance test from it cold: actor, concrete inputs, observable outcome. "Friends episode" titles work as mnemonics for session participants; they fail as specifications for agents who were not there. Keep examples short — but never so short that a reader without session memory cannot derive the test.

4. **B-rule purity** — every B-rule example is expressible in domain terms only. Apply the strip-verbs test from `methodology.md` § Rule Categories: remove the user's name and any UI-mechanic verbs (typing, clicking, hovering, displaying, animating, etc.) from the example. If what remains still describes a valid state transition or invariant, the example is correctly classified as B. If it collapses to "nothing meaningful happens", the example is V mislabeled as B — reclassify (move to a V-rule) or restate (rewrite in domain terms). Timing/debounce/animation are always V regardless of the strip test.

5. **Rule atomicity (single concern)** — every rule covers exactly one concern. Probe by writing one example that neutralises a suspected concern (set it to zero / absent / infinity) while leaving others in play. If the outcome is identical, the neutralised concern is independent of the rest — the rule bundles concerns and should be split. This complements the end-of-Phase-1 structural sanity check (Rule Purity); the lens catches bundling that the principle-bullet form did not surface.

**Typical gaps found:**
- Mechanism language in outcomes ("clicks", "blurs") rather than what the user observably experiences
- Stale hedges surviving from earlier draft iterations
- Placeholder values surviving into Phase 2 examples
- Outcomes vague enough to pass multiple contradictory implementations
- B-rule examples that secretly describe UI mechanics (`Mort types abc → field rejects` masquerading as a domain rule)
- Bundled concerns within a single rule — counter-example detectable: if neutralising concern A leaves the outcome unchanged, A is independent and the rule should be split.

**Calibration:**
- Mechanism language: *"What does [persona] see or experience — without knowing how it's built?"*
- Placeholder: *"What's the real value? If unknown, this is a red card."*
- Mnemonic shorthand: *"Can an agent who wasn't in this session write a test from this example alone?"*
- B/V misclassification: *"Strip the UI verbs from this example — does what remains still describe a valid state transition?"*
- Rule atomicity probe: *"If we set [one aspect of this rule] to its trivial value — zero, absent, infinity — does the outcome change? If not, that aspect is independent and the rule is bundling concerns."*

---

## After the Lens Pass

After presenting the findings:
1. User decides which items to act on — address HIGH items, defer or skip MED/LOW
2. For each acted-on item: add the new example or question card, then ask *"Does this answer imply a rule we should add?"*
3. For per-category passes: continue to the next sub-pass. For the final full pass: run the quorum check (see `methodology.md`), then ask the closing retro question above.
4. Ask: *"Ready to produce the output document?"*
