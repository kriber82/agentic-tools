---
name: example-mapping-methodology
description: Core Example Mapping technique — card types, session structure, facilitation moves, board rendering, and output format
---

# Example Mapping Methodology

## What Is Example Mapping

Example Mapping is a structured conversation technique for fleshing out user stories before development. Originated by Matt Wynne. Goal: surface rules and examples that reveal scope, uncover questions, and build shared understanding — before anyone writes code.

A session uses four card types. Each maps to a distinct concern:

| Card | Color | Represents | Question it answers |
|------|-------|------------|---------------------|
| Story | Yellow | The feature/user story under discussion | What are we building? |
| Rule | Blue | A business rule or acceptance criterion | How does it behave? |
| Example | Green | A concrete scenario illustrating a rule | How does it behave in THIS case? |
| Question | Red | Anything unresolved, unclear, or risky | What don't we know yet? |

## Example Format

Examples are named scenarios, not Gherkin steps. Each example is a minimal two-part statement: **condition snapshot → observable outcome**.

Examples take two forms across a session and grow from one to the other as Phase 1 promotes to Phase 2 (see Session Structure).

**Phase 1 — principle bullets.** Describe the rule's principle in shorthand. Enough for structural review; not yet testable.

```
tier 0 unlocked → unlock hint visible
empty inventory → no trades suggested
disjoint inventory & buy orders → no trades suggested
budget exhausted → policy blocked
```

**Phase 2 — concrete examples.** Same examples, promoted to real names and real data. The form an agent without session context needs to write the acceptance test from.

```
inv: {Logs: 10, Stone: 5}, buy orders: {Seeds: 5, Plant Fibers: 20}
  → trades suggested: empty
inv: {Logs: 10}, buy orders: {Logs: 5}
  → trades suggested: 1 (sell 5 Logs to Alice for 25 gold)
```

Each example is a single condition/outcome pair. Multiple conditions or multiple outcomes → split into multiple examples.

- **Condition**: the state that matters — not "Given the player has navigated to…" but the bare condition snapshot
- **Outcome**: what the user observably sees or cannot do — not "the system updates the record" but "confirmation banner shown"
- **No Gherkin at this stage**: Given/When/Then is the acceptance designer's job. Examples here are seeds, not tests.
- **No placeholders in Phase 2**: by promotion time every value is concrete. Unknown values become red question cards, not brackets.

Capture all examples including obvious ones — each Phase 2 example maps to exactly one acceptance criterion in the handoff.

## Session Structure

### Before Starting

1. Read `CLAUDE.md` and any project context file to ground domain vocabulary
2. Ask user for the story or feature to map — one story per session
3. Establish who the user is (persona) and what they're trying to accomplish

A session runs in two phases. **Phase 1** locks the structural shape (categories, rules, principle bullets, question stubs) at the cheapest possible cost. **Phase 2** promotes the skeleton to fully formulated rules and concrete examples, with scoped lens passes per category.

The user drives discovery throughout. The facilitator asks questions, renders the board, and holds the process. Discovery is bidirectional — rules prompt examples, but examples also prompt rules. When an example surfaces behaviour that isn't covered by any existing rule, ask: *"Does this example imply a rule we haven't named yet?"* When a red card gets answered, ask: *"Does this answer imply a rule we should add?"* Resolved questions are one of the most reliable sources of new rules.

### Phase 1 — Skeleton

Goal: lock the structural shape at the cheapest possible cost. Output is principle bullets and rule titles, not yet testable acceptance criteria.

1. **Name the story** (yellow card) — one sentence, user perspective.

2. **Enumerate categories.** Read the story scope and any prior brainstorm context. Propose the rule categories this story touches — *"This story looks like business + visual + persistence — those become 1.a, 1.b, 1.c. Sound right?"* The user confirms or edits. **Business rules are always 1.a.** See Rule Categories below for the standard vocabulary (B, V, other splits) and numbering.

3. **Iterate sub-passes (1.a, 1.b, 1.c, …)**, one category at a time. Each sub-pass produces:
   - Rule titles (short — typically 5-10 words; no full frames yet)
   - 1-line **principle** example bullets per rule (`empty inventory → no trades`)
   - Question stubs (red cards) for anything unresolved

   **Authorship** within a sub-pass is context-sensitive:
   - *Default (cold start):* facilitator asks; user proposes rules and examples
   - *Rich input* (deep brainstorm or design context exists): facilitator MAY extract rules and examples directly from the input material
   - *Examples not in input* MAY be proposed by the facilitator
   - *Rules not in input* MUST be discovered through facilitation — prefer example-based and open-ended questions (*"What happens when…?"*) over hypothesis-and-confirm (*"Is it true that…?"*)

4. **End-of-Phase-1 structural sanity check.** Before promoting to Phase 2, scan the skeleton for three signals — not a full lens pass, just three cheap checks while bullets are still malleable:
   1. **Failure-coverage gaps** — every non-trivial rule has at least one bullet covering its failure or boundary case
   2. **B/V boundary violations** — apply the strip-verbs heuristic from Rule Categories below; flag any B-rule example that collapses to "nothing meaningful happens" once UI verbs are stripped
   3. **Rule purity** — each rule covers exactly one concern. If a rule's bullets demonstrate multiple distinct concerns (e.g. inclusion semantics + clamping + value formula), propose a split. When the split into single-concern parts isn't straightforward, surface options to the user with a recommendation rather than picking unilaterally.

   Surface findings as a short list. User decides which to act on, then promote.

### Phase 2 — Promotion

Goal: promote the skeleton to fully formulated rules, concrete examples, and (for UI features) a settled rendering reference. Sub-passes 2.a / 2.b / 2.c mirror Phase 1's category sequence.

**2.a Business rules.** For each B-rule:
1. Promote rule title to full frame if needed (most B-rules carry an invariant or formula that the title alone cannot express)
2. Rewrite each principle bullet as a concrete `condition snapshot → observable outcome` example with real names and real data (see Example Format)
3. Preserve the principle bullet as the example's bold-prefix headline (`**All candidates new.**` — see Output Format)

→ **Scoped lens at end of 2.a:** Business + Test + BDD lenses (see `role-perspectives.md`). Run only on B-rules.

**2.b Visualization rules.** UI requires a settled visual draft before V-rules can be fully formulated:
1. **UI draft pass** — write a standalone HTML draft to the story folder (`docs/stories/NNNNN-<slug>/ui-draft.html`) and serve it with the visual brainstorm server (`scripts/start-server.sh --project-dir ...`). Iterate in the browser until the user is satisfied. Use ASCII fallback only if the server is unavailable, the feature has no meaningful visual layout, or the user prefers ASCII.
2. **Short-form V-rule iteration** — the UI draft typically reveals new V-rules or invalidates Phase-1 ones. Iterate the V-rule bullets against the draft until both settle.
3. **Promote V-rules** to full form with concrete examples (same bold-prefix pattern as 2.a)

→ **Scoped lens at end of 2.b:** UX + Test + BDD + Dev lenses. Run only on V-rules.

**2.c Other categories** (persistence, API, calculation, etc.) — promote each category's bullets to full form with concrete examples.

→ **Scoped lens at end of 2.c:** Test + Dev + lenses relevant to the category. Run only on that category's rules.

**Final full lens pass.** After all sub-passes are complete, run all five lenses across the whole map. This catches cross-category issues (V→B reference integrity, cross-rule conflicts, persona consistency) and provides a final spec-quality check.

**Retro question** at the close of the final lens pass: *"Was this final pass valuable, or too much after the per-category passes?"* — capture the answer in the story's retro to tune lens scoping over time.

### Examples Quorum (Gate Before Output)

Do not produce output until ALL of these are true:
- At least 1 happy path Phase 2 example per blue rule — non-negotiable
- For non-trivial rules: advise edge case and failure coverage; document any gaps explicitly in the output rather than blocking
- Every red question is either answered or explicitly marked unresolved (see Park, don't resolve below)
- Story has been confirmed by user as complete
- **For UI-facing features**: Rendering Reference is complete — HTML draft file exists in the story folder and the user has confirmed it; or ASCII fallback has been confirmed if no HTML draft was produced

**Trivial vs non-trivial**: A rule is trivial if it has no boundary conditions, no failure modes, and no variance across user types. Most rules are non-trivial.

### Session End

The facilitator never declares the session over. After the final lens pass and quorum, ask: *"Anything else before producing the output document?"*

### Facilitation Moves

**Challenge vague rules**: *"Is that always true?" | "What happens if [edge case]?"*

**Push for names**: *"Instead of 'the user', who specifically? Give me a name."* (Real names prevent abstract thinking — applies to Phase 2 examples; Phase 1 principle bullets may use category nouns like "empty inventory".)

**Split the rule**: A rule covers exactly one concern. Split signals (in order of importance):
1. **Concern count** — if a rule's frame or examples demonstrate multiple distinct concerns (e.g. inclusion semantics + value formula + clamping), split into one rule per concern. Primary signal.
2. **Frame length** — a frame longer than ~3-4 sentences usually indicates bundled concerns. Quick visual proxy.
3. **Example count** — a rule with more than 5 examples is likely two rules. Quick visual proxy.
4. **Bold-prefix divergence** — if examples need bold-prefix headlines describing *different concerns* (e.g. `**Upper clamp.**` / `**Excluded.**` / `**Formula.**`) the rule is bundled. (Different inputs at the same concern — `**Empty.**` / `**Half-full.**` / `**Full.**` — is NOT a split signal.)

When the split into single-concern parts isn't straightforward, surface the options to the user with a recommendation rather than picking unilaterally.

**Split the story**: If the session produces more than 6 blue rules across all categories, the story likely covers too much ground. Propose splitting by independent user goal or functional slice before continuing.

**Park, don't resolve**: When a question needs stakeholder input, add a red card and move on. Mark `Unresolved — lean: X (because Y)` if the agent has a lean.

Only mark a question RESOLVED inline when the resolution is **mechanical** — unambiguously stated in a referenced source (CLAUDE.md, design doc, or an explicit prior ruling in this conversation). Inferred resolutions, "obvious" defaults, and precedent-based reasoning are NOT mechanical — they go in as `Unresolved — lean: X (precedent: Y from <where>)` and require explicit user confirmation before promotion to RESOLVED. The user later decides; the agent does not pre-empt that decision even on individually low-stakes items.

**Capture all examples**: Do not skip obvious examples — each Phase 2 example becomes an acceptance criterion.

**Triage questions early**: If >5 red cards accumulate, pause and triage: mark each High/Med/Low priority. If 3 or more are High priority and unresolved, recommend resolving them before the follow-up session.

## Board Rendering

Re-render the board after each new card. Use this layout:

```
╔══════════════════════════════════════════════════════════════════╗
║  As a player, I want to craft items and see what I need          ║
╚══════════════════════════════════════════════════════════════════╝
  │
  ├─ [R1]  Items must exist in the recipe database
  │    ▸ E1-1  known item → recipe resolved, ingredients listed
  │    ▸ E1-2  unknown item name → error shown, no crash
  │
  ├─ [R2]  User can mark items as "I buy this"
  │    ┌──────────────────────────────────────────────────────────┐
  │    │ When an item is marked as bought, the recipe tree        │
  │    │ stops at that item — it is not expanded further.         │
  │    └──────────────────────────────────────────────────────────┘
  │    ▸ E2-1  iron plate marked as bought → appears in shopping list, not expanded
  │    ▸ E2-2  iron plate not marked → recipe for iron plate resolved recursively
  │
  └─ [Q1] HIGH  Who decides default buy preferences — user or tool?
     [Q2] LOW   Does the preference persist across sessions?
```

Out-of-scope stories use dashed borders (`+- - -+`) and colon connectors. Active story uses solid double-line box.

**Numbering:**
- Rules: `[R{n}]` — sequential across all stories in the session
- Examples: `E{rule-number}-{example-index}` — e.g. `E1-1`, `E1-2`, `E2-1`
- Questions: `[Q{n}]` — sequential across all stories in the session

**Rule text frame**: When a rule carries a statement beyond its title, render the full text in a `┌─┐ │ │ └─┘` box immediately after the `[R{n}]` title line and before the example lines. Self-contained titles omit the frame.

### Change markers across iterations

In sessions that span multiple board presentations (e.g. iterating between phases, returning after a break, or accumulating cards across sub-passes), mark rules and examples that have **changed since the last board presentation** with a leading `★NEW` or `★CHANGED` glyph in the board rendering.

```
  ├─ [B5]  ★NEW  Zero-price sell offer → take-only candidate
  │    ▸ B5-1  ★NEW  zero-price Seeds → bring 0, take full stock
  ├─ [B3]  Bring minimised
  │    ▸ B3-3  ★CHANGED  bring=9 not 50 (despite infinite balance)
```

Remove the marker once the user has acknowledged the iteration (typically at the start of the next presentation, or once they say "looks good" to the changes).

**Purpose:** lets the user scan for deltas rather than re-reading the full board on each iteration. Especially valuable when a session spans several presentations and the board has grown.

## Rule Categories

Categories are enumerated upfront in Phase 1 (see Session Structure). The default `[R{n}]` namespace works for stories with one concern; most non-trivial stories touch multiple concerns and benefit from a category split. Pure single-concern stories may keep `[R{n}]`.

### Standard namespaces: B / V

- **`[B{n}]`** — Business/domain rule: invariant, calculation, data constraint. No UI language. Testable at the domain layer.
- **`[V{n}]`** — Visualization rule: rendering, display state, interaction behaviour. References domain state (e.g. "when cost-partial") but does not re-state domain logic.

#### B/V boundary heuristic

A B-rule example must be expressible in terms of DOMAIN actors and DOMAIN events. Apply the **strip-verbs test**: remove the user's name and any UI-mechanic language from the example — anything the user does *to* the UI (typing, clicking, tabbing, dragging, hovering, scrolling, swiping, selecting, expanding, collapsing) and anything the UI presents *to* the user as visual feedback (rendering, displaying, animating, transitioning). What remains is the candidate B-form.

- If what remains still describes a valid state transition or invariant → B ✓
- If it collapses to "nothing meaningful happens" → it was V all along

**Always V (regardless of strip test):** timing (debounce, throttle), animation, transition, focus/blur. These describe UI device behaviour, not domain behaviour — even if the strip test would otherwise let them through.

Examples:
- `addInventoryRow(empty, Wood, 42) → inventory becomes {Wood: 42}` — pure function, B ✓
- `when payment-received event fires for order O, O.status transitions pending→confirmed` — stateful domain, B ✓
- `after the 5-minute idle timer expires, the cart enters abandoned state` — accumulated state over time, B ✓
- `Mort clicks Add with valid inputs → the row appears in the inventory panel` — UI mechanic, V ✗
- `Mort types abc; 200ms later debounced commit rejects` — debounce timing, V ✗ (always V regardless of strip test)

### Other splits

The B/V split is not mandatory. The underlying principle is "separate rule categories that are tested at different layers." For a non-UI feature the split might be "calculation rules" vs "persistence rules", or "happy-path rules" vs "error-handling rules." Choose category names that match the story's concerns. Phase 1 enumeration uses these names verbatim (1.a, 1.b, …).

### Numbering with namespaces

Numbering is **sequential across both namespaces** (B1, B2, V3, V4…) so cross-references remain unambiguous. Examples attach to whichever rule they illustrate, prefixed by the rule designator: `B1-1`, `V3-1`. Questions stay `[Q{n}]`.

### Board rendering with namespaces

Add a section separator between namespaces:

```
  ├─ [B1]  ...
  ├─ [B2]  ...
  │
  │  — Visualization —
  │
  ├─ [V3]  ...
  └─ [V4]  ...
```

### Output format with namespaces

Rules are grouped under `### B{n} — Title` and `### V{n} — Title` headings. No other format change needed.

---

## Output Format

```markdown
# Example Map: {Story Title}

**Session date**: {date}
**Story**: {one-sentence user story}
**Persona**: {who the user is}
**Scope**: {what is IN scope} | {what is OUT of scope}

## Rules and Examples

### B1 — {Rule title}
> {Rule statement — precise, testable. Omit if title is self-contained.}

**Examples:**
- **Bold-prefix headline.** {condition snapshot} → {observable outcome}
- **Bold-prefix headline.** {condition snapshot} → {observable outcome}
- *(gap: edge/failure not yet explored)*  ← only if non-trivial rule lacks coverage

### B{n} — {Rule title}
[same structure; rules grouped by namespace per Rule Categories]

**Bold-prefix headline** (recommended, not mandatory): each example carries a 1-5 word bold-prefix summarising the *concern* the example demonstrates — e.g. `**Upper clamp.**`, `**Empty inventory.**`, `**Unpriced target excluded.**`. Skip the prefix on rules with 1-2 examples where the concern is self-evident. Use the surviving Phase 1 principle bullet as the headline — it's already a concern summary by construction.

## Open Questions

Rows are permanent — never delete a question once it is in the table. When a question is resolved, fill in the Resolution cell; do not remove the row. Resolved questions carry historical signal (what was decided and why) and prevent the same question being re-raised in later sessions.

| # | Question | Raised by | Priority | Resolution |
|---|----------|-----------|----------|------------|
| 1 | {question text} | {Business/Test/UX/Dev} | High/Med/Low | Unresolved / {answer} |

## Implementation Notes

> Omit if none emerged. Include decisions that are true and worth recording but not testable acceptance criteria — constraints, architectural choices, or approach decisions that surfaced during the session. Park these as answered questions during facilitation, then promote here in the output.

- {decision or constraint} — e.g. "hold recipes in memory, not re-read per request"
- {decision or constraint}

## Rendering Reference

> Mandatory for any feature with UI output. Omit only if the story has no user-visible rendering.

If an HTML draft was produced during the session, reference it directly:

**UI draft**: [`ui-draft.html`](ui-draft.html) — confirmed by user on {date}

Reproduce ASCII art only when no HTML draft was produced:

### UI Template (ASCII fallback)

```
{ASCII schematic of the panel/section. Use [SLOT] for dynamic values.
Mark optional elements with (optional). Mark always-present elements plainly.}
```

### Fully Filled Example

```
{The template with ALL optional elements present. Use realistic values from the session examples.}
```

### Minimally Filled Example

```
{The template with ONLY mandatory elements. All optional elements absent or replaced with their
hidden/empty state.}
```

## Handoff Package

**Ready for handoff**: Yes / No — {reason if No}
**Blocker questions**: {list any High-priority unresolved questions}
**Coverage gaps**: {list any non-trivial rules missing edge/failure examples}
**Story summary**: {2-3 sentences}
**Key constraints**: {bullet list}
**Riskiest assumption**: {the one open question most likely to invalidate scope}
**Acceptance criterion seeds**: each example above maps 1:1 to one acceptance criterion
```

## Session Quality Signals

**Good session** (all true): More green cards than blue | Red cards have owners | Examples use real data | User said "I hadn't thought of that" at least once

**Troubled session** (any true): Rules keep spawning more rules (scope too large — split the story) | All examples are obvious (push harder on edge cases) | No red cards (team is avoiding conflict) | User answers "it depends" without being able to say depends on what (rule hiding as assumption)

## Anti-Patterns

| Anti-pattern | Signal | Fix |
|---|---|---|
| Solutioning | "We could use a flag for that" | Redirect: *"What should the user see? Not how we build it."* |
| Abstract Phase 2 examples | "A user with permissions" in a final-form example | Push: *"Which user? What permissions exactly?"* (Phase 1 principle bullets may be category-shaped; Phase 2 examples must be concrete.) |
| Rule-less examples | Green cards without a blue parent | Ask: *"Which rule does this illustrate?"* |
| Orphan questions | Red cards with no owner or priority | Triage before closing: who answers this? by when? |
| Premature closure | Non-trivial rules with only a happy path example | Flag missing edge/failure coverage as a gap in the output |
| Auto-resolved questions | Red cards marked RESOLVED with the agent's "lean" interpretation rather than a referenced source | Mechanical-only rule: only the unambiguous-source case promotes to RESOLVED inline. Anything inferred → `Unresolved — lean: X (precedent: Y from <where>)` until the user confirms. |
| Multi-concern rule | A frame >3-4 sentences, >5 examples, or bold prefixes describing different concerns | Propose a split into single-concern rules. When the split is non-obvious, surface options to the user with a recommendation rather than picking unilaterally. |
