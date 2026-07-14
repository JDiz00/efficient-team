---
name: efficient-opus
description: Use when running on Opus 4.8 (or any premium model) and the work is token-heavy, or when the user mentions token conservation, burning tokens, model routing, effort levels, or "use Opus efficiently". Routes heavy lifting to cheaper subagents (haiku/sonnet), right-sizes effort per task, uses bounded Opus subagents/consults for top-judgment review, and keeps decomposition, integration, and final review on the Opus main loop.
---

# Efficient Opus - Premium Model as Conductor

Opus 4.8 costs **$5/$25 per Mtok - 1.7x Sonnet 4.6 ($3/$15), 5x Haiku 4.5 ($1/$5)**.
Sonnet 5 is $2/$10 intro through 2026-08-31 (then $3/$15), but its new tokenizer emits
~30% more tokens for the same text: during intro it nets out near Sonnet 4.6 pricing;
after 2026-08-31 it runs ~30% MORE than Sonnet 4.6 for the same text.
In agentic work, most tokens are *input* (file reads, tool results, logs) - and every one
of them bills at the main-loop model's rate. The fix is structural, not stylistic: keep the
premium context lean and push token-heavy passes into subagents pinned to cheaper models.

**Two mechanics make this real:**

1. **Model routing.** The Agent tool accepts `model: "haiku" | "sonnet" | "opus"`, and
   Workflow `agent()` accepts `{model: "..."}`. **A subagent with no `model` param inherits
   the main-loop model AND its effort** - on an Opus session every unrouted Explore sweep
   silently bills at Opus rates at high effort. Never spawn an unrouted subagent on a
   premium main loop.
2. **Effort routing (new lever in Opus 4.8).** Effort is `low | medium | high | max`;
   Opus 4.8 **defaults to high**, and thinking tokens bill as output tokens ($25/Mtok).
   Effort was recalibrated in 4.8 (medium thinks somewhat more than 4.7's, high slightly
   less, the top tier substantially more). Model choice sets the rate; effort sets how many
   tokens burn at that rate. Route both.

**Subagent gotchas (community-verified, July 2026):**
- In `.claude/agents/*.md` frontmatter use the ALIAS (`opus`, `sonnet`, `haiku`), never the
  full model id - `claude-opus-4-8` is silently ignored and the subagent falls back to
  inheriting the main model.
- Subagents inherit both model and effort from the orchestrator unless set explicitly.
- 3-5 concurrent subagents is the sweet spot; beyond that, merging their reports costs more
  than the parallelism saves.

## Routing Table

| Delegate to | Work | Why |
|---|---|---|
| **haiku** | Broad search sweeps, file/dir inventory, log reduction, test-output triage, summarizing long docs/diffs, mechanical rote edits | 5x cheaper than Opus; these tasks are recall, not judgment |
| **sonnet** | Implementation subagents, bounded code edits, running tests, playwright-cli browser verification, research scans, doc reading, candidate patches | ~1.7x cheaper (2.5x per token at Sonnet 5 intro, ~1.9x for the same text after the tokenizer penalty); strong enough to work independently within a tight handoff packet - Opus still reviews the evidence before final |
| **opus subagent** | Deep code review, security review, tricky bug diagnosis - anything needing full-file ingestion at top judgment | Same rate as the main loop, but the bulk input lands in a disposable context - can preserve the main context/cache or avoid a compact |
| **opus** (main loop - never delegated) | Decomposing ambiguous work, resolving conflicting subagent reports, integration across shared files, risk calls, final review, user-facing synthesis | This is what the premium buys |

Note the opus-subagent row: it bills at the same rate as the main loop, so use it only
when isolated bulk ingestion preserves the main context and cache or avoids a compact -
not for small one-off reviews, where the handoff and report overhead costs more than it
saves.

## Effort Table

| Effort | Use for |
|---|---|
| **low** | Mechanical subagent work (pair with haiku/sonnet); skills doing formatting, linting, simple checks - skill frontmatter supports `effort: low` |
| **medium** | Routine implementation and drafting where high is overkill |
| **high** (default) | Main-loop judgment; leave it alone unless you have a reason |
| **max** | One deliberately-chosen hardest bounded problem, not a session default - thinking tokens bill as output |

Cheap pre-delegation reflexes that avoid spawning anything: use a semantic/intent code-search
tool if you have one (far cheaper than grep+read across many files), a code-graph query for
architecture questions, and read only the line ranges you actually need.

## Context Hygiene (token burn is compounding, not additive)

- CLAUDE.md loads before your code and persists in context every turn, never evicted - a
  5k-token CLAUDE.md costs 5k on every single turn. Keep it lean.
- `/clear` between unrelated tasks; `/compact` early (~60% utilization), not at the wall -
  the earlier the compact, the better the summary.
- Big tool outputs (logs, test runs) stay in context for every subsequent message - offload
  them to disk and read back only what matters.
- Unused MCP server schemas are a standing per-turn tax - trim tool bloat.
- A small, stable premium context stays prompt-cached; cache stability is the biggest
  silent lever. Every unrouted mega-read that forces a compact also nukes the cache.

## Two Operating Modes

**Mode A - Opus conductor** (main loop = `claude-opus-4-8`): best quality ceiling. All
delegation carries an explicit `model` (and effort where the harness allows) per the tables.
Opus itself reads only what the decision layer needs - subagents return distilled evidence,
not raw dumps.

**Mode B - Sonnet main + Opus consult** (main loop = `claude-sonnet-5` or `claude-sonnet-4-6`):
cheapest way to keep Opus in the loop. Run normal work on Sonnet; for the genuinely hard call
(architecture decision, plan review, final integration review), spawn one subagent with
`model: "opus"` and a complete handoff packet. One Opus consult on a lean packet costs a
fraction of an Opus main loop ingesting the whole session.

Pick per session with `/model`. Heavy build day on unfamiliar code - Mode A. Routine
feature work - Mode B. Tiny fixes - plain Sonnet, skip this skill entirely.

## Handoff Packets

Write delegated prompts as if the subagent has zero chat context (it does). Include only:

- Repo path and the exact objective, one sentence.
- Files/packages/surfaces in scope - and what is explicitly out of scope.
- Evidence format to return: file:line refs, commands run, diffs, failures, uncertainties.
- Verification commands or browser flows to run, and what success looks like.
- Stop conditions: if reality doesn't match the prompt, a command fails after one retry, or
  the task needs out-of-scope files - stop and report, don't improvise.

## Vetting Delegated Work

Subagent reports are leads, not facts. Before acting on a high-impact finding, opening a PR,
or telling the user it's done: reopen the cited files, confirm the line refs or failures,
review the final diff against the task. Cheap models gather signal; truth-judgment stays
with the premium model.

## When NOT to Delegate

- Tiny tasks - the handoff packet costs more than doing it.
- Highly coupled edits across shared files - coordination overhead exceeds savings.
- Validation that itself needs delicate judgment - keep it in the main loop.

## Optional: enforce it with a hook

The routing above is a discipline the operator applies. If you want it enforced automatically,
a `PreToolUse` hook can auto-pin unrouted subagent spawns on a premium main loop (recall work →
haiku, judgment → opus, everything else → a sonnet floor), while never overriding an explicit
`model`. That hook is not bundled here — it's an optional add-on you'd write for your own setup;
the skill works fully without it.

## Honest Expectations

For codebase-heavy work with independent slices, 2-4x cost reduction and 2-4x wall-clock
speedup (parallel subagents) are realistic - workload-dependent, not guaranteed. The
multiple is smaller than on a Fable main loop because Opus's premium over Sonnet/Haiku is
smaller; the savings come from (a) cheaper models absorbing input-token bulk, (b) effort
right-sizing, and (c) the premium context staying small enough to stay cached and never
compact. A reference point from production write-ups: one Opus orchestrator plus four
Sonnet workers runs ~30-40% cheaper than five Opus agents, depending on the token mix
(equal-token math at Sonnet 4.6 rates gives ~32%).

*Adapted from BuilderIO/skills `efficient-fable` (delegation discipline, handoff packets,
vetting); re-geared for an Opus 4.8 main loop with effort routing, current pricing, and
community-verified subagent gotchas. Pricing verified 2026-07-12 - re-verify via
`/claude-api` if quoting later (Sonnet 5 intro pricing ends 2026-08-31).*
