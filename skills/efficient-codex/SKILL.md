---
name: efficient-codex
description: Use when running Codex on GPT-5.6 and the work is token-heavy — large repo reads, multi-file implementation, broad review, log or test triage — or when the user mentions cost, usage limits, model routing, effort levels, or "use Codex efficiently". Routes each Codex invocation to the cheapest capable GPT-5.6 tier (Luna for mechanical sweeps, Terra for everyday engineering, Sol for architecture/security/review) by selecting the model at call time. Do not trigger for tiny questions the active agent can answer immediately without repository work.
---

# Efficient Codex — Route Each Call to the Cheapest Capable Tier

GPT-5.6 Sol costs **$5/$30 per Mtok — 2x Terra ($2.50/$15), 5x Luna ($1/$6)**. In agentic
work most tokens are *input* (file reads, tool results, logs), all billed at the running
model's rate. On a default-Sol Codex setup, a mechanical file sweep bills at Sol rates for no
judgment gain. Fix: pick the model per invocation.

## The mechanism (what actually works on this build)

**Choose the model when Codex is invoked** — pass it to `codex exec` / the CLI as `-m` /
`--model`, or use a wrapper's tier flag. This is caller-routed, exactly like efficient-fable
and efficient-opus route Claude's subagents: the operator picks the tier, the model doesn't
have to.

```bash
codex exec -m gpt-5.6-luna  -c model_reasoning_effort='"low"'    "<mechanical task>"
codex exec -m gpt-5.6-terra -c model_reasoning_effort='"medium"' "<everyday engineering>"
codex exec -m gpt-5.6-sol   -c model_reasoning_effort='"high"'   "<architecture / security / review>"
```

**Why not in-session subagent pinning?** Verified on Codex CLI 0.144.4 (2026-07-14) with
unique fingerprint tokens: a per-agent **model/effort pin in `~/.codex/agents/*.toml` does
not take effect** — a spawned subagent inherits the main thread's `gpt-5.6-sol`/high
regardless of the pin. The `config.toml [agents.<name>]` model registry likewise did not
change the spawned model, and the `spawn_agent` tool's `model` argument is not in its
declared schema (accepted nondeterministically). So autonomous Sol-led per-task delegation by
tier is not reliable on this build; the reliable lever is model-at-invocation
(`codex exec -m gpt-5.6-<tier>`). (OpenAI's own `use_agent_identity` / `enable_fanout` flags
are still "under development" — if/when per-agent model pinning takes effect, the
`examples/agents/*.toml` in this package become the pins.)

## Routing Table

| Tier (invoke with) | Effort | Work |
|---|---|---|
| **gpt-5.6-luna** | low | Locating files/symbols/routes, repo inventories, dependency lists, classifying errors/logs/TODOs, exact-mapping renames, formatting cleanup, repetitive fixtures/stubs, extracting requirements, summarizing bounded files, pattern checks |
| **gpt-5.6-terra** | medium | Feature implementation, ordinary bug fixes, behavior-preserving refactors, writing/updating tests, library integration, API handlers and app logic with clear requirements, exploration needing engineering interpretation, docs tied to code, running builds/tests/lint/types, normal PR review |
| **gpt-5.6-sol** | high+ | Architecture and system design, ambiguous/conflicting requirements, difficult root-cause analysis, security/auth/crypto/migrations, large cross-cutting refactors, adversarial review, final arbitration, release-readiness judgment |

Never route architecture, auth, cryptography, migrations, concurrency, production incidents,
destructive operations, or unclear bugs to Luna. When uncertain between adjacent tiers, start
cheaper and re-run one tier up if the result shows uncertainty or fails verification. The
objective is not to use all three — it is the lowest-cost tier that reliably does the job.

## Effort Ladder

| Effort | Use for |
|---|---|
| **low** | Luna default: lookup, extraction, bounded transforms, simple edits |
| **medium** | Terra default: ordinary implementation and debugging |
| **high** | Sol default: multi-step work, unfamiliar systems, meaningful tradeoffs, broad review |
| **xhigh** | Difficult diagnosis, architecture, security, final high-value review |
| **max** | Rare single-thread problems where depth matters more than usage |
| **ultra** | Rare: goes beyond a single-agent run — uses parallel subagents for work that splits into separable workstreams |

Model choice sets the rate; effort sets how many tokens burn at that rate. Route both. Do not
use max or ultra merely because a task is long — long repetitive work is a Luna/Terra job.

## Handoff Packets

Write each Codex invocation as a self-contained brief (Codex sees only the dir + your prompt):

- Exact scope, one sentence; files/directories in scope; non-goals.
- Whether Codex may edit or must stay read-only.
- Expected return format: findings/changes, files touched, commands run, test results, uncertainty.
- Verification required and what success looks like.
- Stop conditions: reality doesn't match the prompt, a command fails after one retry, or the
  task needs out-of-scope files — stop and report, don't improvise.

## Adversarial Review Split

For consequential changes, separate builder and reviewer across two invocations: a Terra call
(`-m gpt-5.6-terra`) implements; a Sol call (`-m gpt-5.6-sol`, read-only) reviews the diff for
regressions, wrong assumptions, missing tests, security, edge cases, unneeded complexity; the
builder addresses accepted findings. Low-risk routine work: a Terra self-review is enough — do
not spend Sol on every edit.

## Vetting

Model output is leads, not facts. Before acting on a high-impact finding or declaring done:
inspect the resulting diff yourself and run the checks (focused tests, types, lint, build);
distinguish pre-existing failures from regressions. Cheap tiers gather signal; truth-judgment
stays at the Sol tier (or with you).

## Verifying a route actually took

Never trust a model's self-report of its own name. Check the rollout log:
`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, field `turn_context.payload.model` (main
thread) or `turn_context.collaboration_mode.settings.model` (subagent thread). The
package's `test/run-tests.sh --live` does exactly this, fail-closed.

## Honest Expectations

Per-token, Terra costs 2x less than Sol and Luna 5x less for routed calls — that is the
guaranteed part. End-to-end savings on a real task depend on the workload mix (how much of it
is genuinely mechanical vs judgment, plus any Sol review passes and re-runs), so the honest
claim is "route each call to the cheapest capable tier; savings vary by workload," not a fixed
multiple. Codex-side routing is discipline, not an enforced mechanism — the verification step
above is part of the contract.

*Companion to efficient-fable and efficient-opus (Claude Code). Sol/Terra/Luna pricing, the
effort ladder, and the caller-routed mechanism verified on Codex CLI 0.144.4, 2026-07-14 —
re-verify before quoting later.*
