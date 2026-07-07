<!-- MANDATORY-READ: cost-awareness -->
# Cost-awareness (personal, cross-repo)

> **MANDATORY READING.** `~/.claude/CLAUDE.md` requires every session to read this
> file in full before other work, and to apply it. This is the single source of the
> cost-behavior rules — CLAUDE.md only points here.

Distributable, self-contained cost-behavior guide. Referenced from
`~/.claude/CLAUDE.md`; also bundled in the session-logger distribution zip.

**Why this exists** — grounded in a real AI-spend analysis (2026-07-06, a
~100%-Opus usage window): **context re-reading is the dominant cost, not output.**
Cache-read was 93% of tokens and ~42% of cost; cache-create another ~35%. Every turn
re-reads the whole cached prefix, so **a big/long-lived context makes every turn
expensive**, and an idle >5 min lets the cache TTL lapse and re-pays cache-create.
The levers below all target that.

---

## At the start of each session and on each topic switch — two quick checks

Do these proactively (not only when asked). Keep each to one short line; if the
answer is "current setup is fine," a single sentence or silence is enough — don't
turn it into a ceremony.

1. **Model fit — is Opus actually needed?** If the task is mechanical, well-scoped,
   search/lookup, routine edits, or drafting, **propose Sonnet** ("This looks like
   Sonnet-tier work — want me to switch? `/model sonnet`"). Reserve Opus for hard
   reasoning, ambiguous design, tricky debugging. The user decides; you just surface it.

2. **Session freshness — is the context large or the topic new?** If context is
   already large (statusline bar yellow/red, `↻new?` hint) **or** the new request is
   unrelated to what filled the current context, **propose a fresh session / `/clear`.**
   A large context is a per-turn cost multiplier: everything in it is re-read every turn.

> Assertiveness is currently set to **every session / topic start**. If this feels
> naggy in practice, dial it back to *threshold-triggered* (stay quiet until context
> is large or the task looks Opus-overkill) by editing this file.

## During work — habits that keep context lean

- **Offload large reads to a subagent for targeted questions.** If you only need a
  fact, a symbol, or a conclusion out of a big file/log/dir, dispatch an Explore /
  general-purpose subagent and keep only its answer — don't pull the whole file into
  the main context, where every later turn re-caches it. Read directly into main
  context only when you'll actively edit or repeatedly reference the content.
- **Route subagents to Sonnet.** Explore / search / review / summarize subagents run
  fine on Sonnet and inherit the parent (Opus) by default. Pass `model: sonnet` (or
  use a Sonnet-pinned agent) unless the subagent genuinely needs Opus reasoning.
- **Avoid long mid-task idles.** A gap >5 min lets the ephemeral cache expire, so the
  next turn re-pays full cache-create (the statusline 💤 timer turns red at 5 min).
  Batch clarifying questions and stay engaged through a task rather than stepping away
  mid-flight.

## The one-line rationale to remember

Cost ≈ context size × turns. Smaller context (fresh sessions, subagent-offloaded
reads), cheaper model where it suffices (Sonnet), and no idle cache-expiry are the
three levers that move the bill.
