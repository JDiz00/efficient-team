---
name: efficient-team
description: Use when you invoke /efficient-team or say "efficient team", "power team on", "enable the efficient stack", or want Claude and Codex running their efficiency disciplines at the same time — efficient-opus for Claude (Opus in the lead) and efficient-codex for Codex (route each Codex call to the cheapest capable GPT-5.6 tier). Also handles "efficient team off" / "disable efficient team". Loads efficient-opus discipline for the Claude session and, from then on, routes every Codex call Claude makes to the right GPT-5.6 tier.
---

# Efficient Team — One Switch, Both Agents

Enables the paired efficiency disciplines: **efficient-opus** for the Claude session (premium
model as conductor, cheap subagents absorb token bulk) and **efficient-codex** for every
Codex call from this machine (each invocation routed to the cheapest capable GPT-5.6 tier).
Both companion skills ship in this package: `efficient-opus`, `efficient-codex`.

## Turning ON

1. **Load the Claude half.** Invoke the `efficient-opus` skill now and operate under its
   routing/effort/context-hygiene rules for the rest of the session.
2. **Check the main loop.** This skill never switches the main-loop model (only you do, via
   /model). If the session is not already on an Opus-family model, say so in one line and
   give the command as a copyable block:
   ```
   /model claude-opus-4-8
   ```
   Then continue — the discipline does not depend on the choice.
3. **Arm Codex routing.** From now on, route every Codex call to the right tier (table
   below) via `codex-route` (shipped in this package). Optionally set the discipline flag so
   any wrapper that reads it auto-carries `Use $efficient-codex.` into Codex's context:
   ```bash
   touch ~/.codex/efficient-codex.on
   ```
   (The flag is a convenience; `codex-route` routes regardless of it.)
4. **Verify + report** in exactly this shape:
   `Efficient Team: ON · Claude=efficient-opus loaded · Codex routing armed (codex-route)`

## Routing every Codex call (the important part)

The Codex model is chosen **when Claude invokes Codex**, not by Codex mid-run (in-session
subagent pinning is not reliable on this build — see efficient-codex). So while Efficient Team
is on, Claude picks the tier per call:

| Call is… | Route to | Tier flag |
|---|---|---|
| Mechanical: inventory, file/symbol lookup, extraction, classification, formatting, repetitive edits | **gpt-5.6-luna** / low | `--luna` |
| Everyday engineering: implement, ordinary bug fix, refactor, tests, normal PR review, build/test/lint | **gpt-5.6-terra** / medium | `--terra` |
| Judgment: architecture, security/auth/crypto/migrations, hard debugging, adversarial review, arbitration | **gpt-5.6-sol** / high | `--sol` |

**Route each call with `codex-route`** (shipped in this package, on `PATH` after install):
```bash
codex-route --luna  "inventory every file importing db.py" -C ~/proj
codex-route --terra "implement the /health route per SPEC"  -C ~/proj
codex-route --sol   "adversarial review of this auth diff"  -C ~/proj --xhigh
```

Tier flags map to `-m gpt-5.6-<tier>` with the tier's default effort; explicit `--high` /
`--xhigh` overrides the effort but keeps the tier's model; conflicting tier flags exit 2.
`codex-route` requires a tier flag (exits 2 without one). When you call `codex exec` directly,
pass `-m gpt-5.6-<tier>` yourself.

## Turning OFF

```bash
rm -f ~/.codex/efficient-codex.on
```
Confirm removal, stop applying efficient-opus discipline, stop adding tier flags, and report:
`Efficient Team: OFF · flag removed · efficient-opus discipline released`

## Notes

- The flag is **machine-wide and persistent**: it makes wrapper calls that read it carry the
  skill directive in every session, and survives restarts until turned off. Say this the first
  time it's enabled in a session so no one is surprised later. (It only carries the routing
  *skill*; the tier *choice* is Claude's per call.)
- Verify a route took effect from the rollout log, not a self-report — see efficient-codex.
