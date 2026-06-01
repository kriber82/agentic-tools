---
name: code-properties
description: Reviews changed production files against a checklist of engineering properties — functional (correct/secure/resilient), locally-understandable (intent/names/cohesion/altitude/etc.), and maintainability (directed/idiomatic). Proposes improvements per violated property. Note — partial overlap with general-review (correctness/resilience) and screaming-architecture (intent/names); this is intended, the passes surface different genuine findings.
id_prefix: PROP
estimates_effort: false
---

# Pass: Code Properties

Review **all production code files changed in this branch** for adherence to the
properties below. For each property a file conflicts with, propose improvements.
Process files in dependency order: **start at the construction root / main and
work toward the edges of the system.** Output results per file before proceeding.

## Properties

### 1) Functional Properties

- **Correct** — code does what the programmer intended under all relevant
  conditions: edge cases handled, concurrency sound, language and libraries
  behaving as assumed. Failure mode: code that reads plausibly but misbehaves
  silently — an unenforced type constraint, blocking I/O behind an async surface.
- **Secure** — TODO.
- **Resilient** — each external dependency has a defined failure path that
  surfaces where it can be acted on; a failure in one part does not silently
  abort or corrupt unrelated work. Swallowed errors are a decision, not an
  accident.

### 2) Properties of locally understandable code

- **Reveals intent** — at each level, code expresses what it is for using the
  vocabulary native to that level (business process, zip archives, Firestore
  documents). A reader understands what a unit does and why it exists without
  reading the levels below it.
- **Self-contained** — all information needed to understand a unit is visible at
  that level; other files are unnecessary, or as few and as close as possible.
- **Honest names** — names reveal what a unit does: concrete (not process),
  complete (no hidden side effects), accurate (no lies by omission or
  misdirection).
- **Fits in your head** — a unit has ~5–7 things to track (lines in a function,
  methods in a class, modules in a package).
- **One abstraction level** — a unit operates at a single altitude; orchestration
  doesn't mix with implementation detail.
- **Semantic grouping** — things are grouped because they belong to the same
  concept, not because they happen to recur or co-vary.
- **(Cohesive** — things that depend on each other are together; things that
  don't are apart.) → follows from above?
- **Explicit** — dependencies and effects flow through visible channels
  (parameters, return values, types), not global state or implicit ordering.
- **Symmetric** — analogous things look analogous; different structure signals
  different meaning. (TODO: relevant within business code, not between different
  adapters.)

### 3) Other properties increasing maintainability

- **Directed** — dependencies point from volatile toward stable: infrastructure
  toward domain, not the reverse. Configuration is a layer, not a side effect of
  importing a module.
- **Idiomatic** — code uses the language and ecosystem as designed: current
  syntax, standard constructs, library conventions. Non-idiomatic code signals
  intent it doesn't mean and forfeits guarantees the platform provides.

## Mapping to finding entry

Each proposed improvement becomes a finding.

- `native_metric`: `engineering-property adherence (severity of the violated property)`
- `native_score`: severity of the violation — `high | med | low`. (Higher = more
  likely to cause defects or to mislead readers of central code.)
- `confidence`: your real read that this is a genuine violation, not taste.
- `effort`: **omit** — this pass does not estimate effort (`estimates_effort: false`).
- `impact-evidence`: the concrete violation, naming **which property** and the
  specific symptom — e.g. "Resilient: `catch {}` swallows the network error so a
  failed fetch silently returns stale data".

Name the violated property in every finding so provenance is unambiguous (this
pass overlaps others — the property name is how a reader tells findings apart).
Do **not** emit a cross-pass impact number; the orchestrator assigns impact.

## Detail file schema

```markdown
# Code Properties — findings

scope: <BASE>..<HEAD>

<!-- optional: brief per-file pass notes, root → edges -->

## PROP-01 — <short title>
- native_metric: engineering-property adherence (severity of the violated property)
- native_score: <high | med | low>
- confidence: <low | medium | high>
- property: <Correct | Resilient | Reveals intent | Honest names | Explicit | Directed | Idiomatic | ...>
- impact-evidence: <property + concrete symptom>

<prose: file:line, what conflicts with the property, why it matters, proposed code change>

## PROP-02 — ...

<!-- end:code-properties -->
```

## Return to orchestrator

Compact row-summary, one line per finding:
`id | title | native_score | confidence | property | impact-evidence`.
Regenerable from the detail file headers; ephemeral.

## Reminder

Findings only. The parent skill's autonomy gates apply: do not edit, stage,
commit, or merge any file outside `docs/reviews/<slug>/`. Propose changes; do not
apply them.
