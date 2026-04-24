# Implementation bring-up — session lessons (ARCH-01 → ARCH-04)

Captures process-level meta-lessons from the first four P0s that landed (ARCH-01 skeleton, ARCH-03 CI gate, ARCH-02 canonical module, ARCH-04 resolved-settings YAML). These are lessons about *how to make this project move*, not about NixOS or compliance specifically — orthogonal to the existing `lessons-learned.md` PRD-phase content.

## The session

Five PRs in one sitting:

| PR | What landed | CI iterations |
|---|---|---|
| #20 | ARCH-01 skeleton + ARCH-03 CI gate | 4 |
| #21 | Wiki compile: skeleton + CI + GHA stack | 1 |
| #22 | ARCH-02 canonical module | 1 |
| #23 | ARCH-04 resolved-settings YAML | 1 |
| #24 | Wiki compile: canonical-config | 1 |

Total: five green CI runs, eight merged commits, three new wiki articles, four new gotcha entries, four raw notes.

## Lesson 1 — When there's no local `nix`, CI IS the evaluator

The development environment on this project has no `nix` binary. For a Nix-heavy project, that *sounds* crippling. In practice it's fine — the CI gate (`nix flake check` + `nix eval` + statix + deadnix) runs on every push and gives ground truth in 1–2 minutes.

**Rule that emerged:** write Nix conservatively (no clever evaluator tricks, no untested option names), push, let CI tell you what's wrong. Expect ≥1 CI iteration on every non-trivial PR. Budget for it; don't try to be perfect pre-push.

ARCH-01/03 took 4 CI iterations — each pass surfaced one more hidden issue:
1. `DeterminateSystems/magic-nix-cache-action` required FlakeHub auth.
2. `checks.eval = drvPath` is a string, not a derivation — rejected by `nix flake check`.
3. `statix` flagged empty `{ ... }:` patterns.
4. `deadnix` flagged unused `self` binder.

Each fix was obvious once the error was in front of us. No amount of pre-push rumination would have caught all four — some of these patterns look fine in isolation and only break in combination. **The meta-lesson: CI is not a gate, it is a tight feedback loop.**

## Lesson 2 — Supply-chain drift in CI actions is real and fast

`DeterminateSystems/magic-nix-cache-action` changed between early 2025 (zero-config, no auth) and today (requires FlakeHub registration). The change was silent from the action's perspective — workflows that worked last quarter fail now. The research agent's training-data recommendation would have been correct in 2024; it was wrong in April 2026.

**Rule:** never trust action pins without live verification. `@main` is a supply-chain risk even for reputable orgs. Pin to commit SHAs; enable Dependabot; re-verify the whole stack every 6 months.

## Lesson 3 — The raw → compile → wiki loop works

The vault's convention is:

1. Drop research/learnings into `raw/` as you work.
2. When the time is right, "compile" — distill into wiki articles with cross-links.

Tested across this session. Every TODO produced at least one raw note; at two points we did batch compiles (PR #21 covered ARCH-01+03; PR #24 covered ARCH-02+04). The compile pass is ~10 minutes of work and produces materially better wiki content than trying to write finished articles on the first pass.

**Rule:** raw notes do not have to be polished. They are source material; informal is correct. Compile them when the concept is settled, not when the raw note is "done."

## Lesson 4 — One concept, two artifacts — audit vs runtime

`modules/canonical/default.nix` and `docs/resolved-settings.yaml` are the same information in two views. One is consumed by the Nix evaluator; the other is consumed by an auditor. Both exist because neither audience can use the other's format.

**Rule that emerged:** for any cross-framework resolved decision, produce a Nix-consumable view (runtime truth, type-checked, module-system integrated) and a YAML-consumable view (audit truth, provenance-rich, rejection reasons preserved). Enforce agreement via tests (ARCH-17) once those tests exist; enforce via PR review until then.

This generalises beyond canonical config. Expect the same pattern for the evidence-generation framework (ARCH-10), the threat-model module (ARCH-08), and the model registry (AI-23).

## Lesson 5 — PR cadence: one TODO, one PR, then compile

Granular PRs with tight scope cleared CI faster and were easier to review. Anti-pattern that was considered and rejected: one mega-PR with ARCH-01/03/02/04 bundled. Would have taken 10+ CI iterations and review would have been miserable.

**Rule:** one P0 TODO per PR is the sweet spot for this project. Wiki compiles are cheap enough to batch 2–3 TODOs per compile PR. Avoid ever having more than one open PR on the same module directory — CI cache and review attention don't scale.

## Lesson 6 — ARCH-06 (FHS-path audit) got 80% preempted by ARCH-03

The legacy-FHS-path lint in the CI workflow (`grep -rnE '/(usr/bin|usr/sbin|sbin)/' modules/ hosts/`) already catches almost everything ARCH-06 was supposed to do manually. ARCH-06 remains on the list for one reason: the CI lint only covers `modules/` and `hosts/`, not PRD prose or comment blocks. A future sweep of the PRD files is still worth doing. But the preemptive CI rule got us 80% of the value with 5% of the effort.

**Rule that emerged:** when a P0 TODO is primarily about "don't let X happen," prefer a lint that prevents X over a one-shot audit that found X-once. The lint keeps working forever.

## Lesson 7 — `nixos-implementation-patterns.md` was never indexed

Found during the ARCH-01/03 compile pass: `wiki/architecture/nix-implementation-patterns.md` exists but was missing from `_index.md`. Presumably dropped from the index at some point and never re-added. Fixed as a side effect.

**Rule:** every compile pass should include an incidental audit of the topic's `_index.md` against the actual files in the directory. Cheap to check; easy to miss.

## Open meta-questions

- **When do we commit `flake.lock`?** Current state: CI generates on every run. Works, but reproducibility is drift-prone. The first time someone with a `nix` CLI runs the project, they should commit a lock and we delete the bootstrap step. Tracked informally; not yet a TODO.
- **When does ARCH-17 (acceptance-criteria test harness) actually land?** It is the enforcement mechanism for canonical-YAML agreement. Currently P2. Would benefit from promotion to P1 if more canonical-consuming modules land first.
- **Do we split ARCH-06 now?** If the CI lint covers 80%, the remaining 20% (PRD prose) could be a P2 sweep rather than a P0.

## Suggested wiki compile targets

- `wiki/review-findings/lessons-learned.md` — extend with a new section "Implementation Bring-Up Lessons" covering lessons 1, 2, 4, 5, 6 (the generalisable ones).
- `wiki/review-findings/session-cadence.md` (new) — if the "one TODO per PR + batched wiki compiles + CI iterations" rhythm is worth codifying beyond the lessons page.

Not compile-worthy on their own: lessons 3 and 7 — meta about the vault itself, not about the project.
