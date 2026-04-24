# Session pause checkpoint — 2026-04-24

Snapshot of nix-flake project state at a deliberate pause point. Captures what landed, what's next, what's blocked, and the patterns that should carry forward. Designed so a fresh session can read this + `todos/README.md` and orient in under five minutes.

## State of main

- Main is green. Last commit: PR #31 (wiki compile for ARCH-06 + INFRA-03).
- 12 PRs merged in this session (10 feature + wiki compiles + 1 hotfix).
- 7 of 16 P0 TODOs complete.
- CI gate operational: `nix flake check` + `nix eval` + `statix` + `deadnix` + two-layer FHS-path lint.

## Completed P0 TODOs

| # | ID | PR | What shipped |
|---|---|---|---|
| 1 | ARCH-01 | #20 | Flake skeleton, six module stubs, `hosts/ai-server/`, nixpkgs pinned to nixos-24.11 |
| 2 | ARCH-03 | #20 | GitHub Actions workflow: flake check, eval, statix, deadnix, FHS-path lint |
| 3 | ARCH-02 | #22 | `modules/canonical/default.nix` — typed `options.canonical.*` for all 15 Appendix A subsections |
| 4 | ARCH-04 | #23 | `docs/resolved-settings.yaml` — 29 conflict-resolution rows with provenance |
| 5 | ARCH-05 | #26, #27 | sops-nix flake input (pinned pre-Go-1.25), `modules/secrets/default.nix`, 10 secret declarations, prose normalised across PRDs |
| 6 | ARCH-06 | #29 | 3 broken audit rules fixed, narrow docs/ CI lint for `"-w /usr/bin/...` added |
| 7 | INFRA-03 | #30 | `environment.etc."login.defs"` overrides replaced with `security.loginDefs.settings.*`; xserver.videoDrivers annotated; Protocol 2 prose clarified |

Wiki compiles: PRs #21, #24, #25, #28, #31.

## Next up (P0 queue)

- **INFRA-01** — rewrite `lan-only-network` firewall to nftables with correct egress. Tightly coupled to INFRA-02.
- **INFRA-02** — bind all listeners (Ollama, app API, SSH) to loopback or LAN NIC explicitly. **Suggested: batch with INFRA-01 in one PR** since they're two halves of the same module's intent.
- Then the AI-side Ollama-specific broken-Nix fixes: **AI-06 → AI-01 → AI-02 → AI-03 → AI-07 → AI-05**. All are PRD-prose fixes with the same "no module code yet; fix the broken snippet in the PRD so future implementers don't copy-paste it" pattern.
- **AI-04** is a decision item (SEV/TDX vs signed-risk-acceptance for live-memory ePHI). Blocked on the human. Flagged at the bottom of `todos/README.md`.

## Open decisions needing human input

Copied from `todos/README.md` Open Decisions section; nothing has been resolved yet:

1. **AI-04 — target hardware path for ePHI.** SEV-SNP, TDX, or accepted-risk letter? Consumer NVIDIA forces option 3. Ripples into HIPAA §164.308(a)(1)(ii)(B), HITRUST privacy, EU AI Act high-risk classification.
2. **ARCH-08 — single-tenant declaration.** Confirm before AI-26 tiered guide is finalised.
3. **App-layer ownership.** OWASP residual-risk (AI-12), EU AI Act logger (AI-22), RAG governance (AI-20) all assume an orchestrator team. If none exists, "aspirational" fraction is ~100%.
4. **HITRUST scope.** If aspirational only, defer 19-domain rewrite; drop L5-maturity cleanup to P3.
5. **Quarterly review owner.** ATLAS refresh + framework-drift watch (ARCH-18) needs a named human or bead-assigned agent.
6. **IPv6 in/out of scope?** INFRA-01 firewall decision.
7. **Physical access in threat model?** Gates INFRA-18 (Secure Boot) and INFRA-20 (Thunderbolt DMA).

## Patterns worth carrying forward

Condensed from `wiki/review-findings/lessons-learned.md` entries 20–27. If reading this cold, also read those entries in full.

1. **CI is the evaluator, not a gate.** No local `nix` CLI; budget for ≥1 CI iteration per non-trivial PR.
2. **`gh run watch --exit-status` is unreliable.** Always check `gh pr view <n> --json mergeStateStatus,statusCheckRollup` directly before `gh pr merge`. This caught me once — broken PR #26 landed on main and needed hotfix PR #27.
3. **Flake inputs without a rev are time bombs.** Pin to commit SHA. Example: `github:Mic92/sops-nix/3b4a369df9...`, not `github:Mic92/sops-nix`.
4. **Audit-vs-runtime artifact pattern.** One concept → two files. `canonical.nix` (Nix-consumable) + `resolved-settings.yaml` (audit-consumable). Expect this shape for evidence generation, threat model, model registry.
5. **Linters beat prose conventions.** Module system says `{ ... }:` is fine; statix rejects it as pattern-empty; statix wins because it runs on every PR.
6. **Two-layer lint pattern.** Broad regex on code (`modules/`, `hosts/`); narrow regex on docs (`"-w /usr/bin/...`). Test: would the regex fire on the comment explaining it? If yes, lint is impossible — do a sweep.
7. **PR cadence: one P0 per PR, batch wiki compiles.** Keeps review tight, CI cache warm. Never two open PRs on the same module tree.
8. **Secrets module pattern:** `sops.defaultSopsFile` path literal + placeholder file + `validateSopsFiles = false` + `age.generateKey = false` → eval works without real encryption.
9. **Module-system rule:** once you declare `options.*`, every config must live under `config.*`. No mixing top-level `sops = { ... }` with `options.*`.
10. **Prefer lints over sweeps — when the regex distinguishes.** ARCH-06 got 80% preempted by the ARCH-03 CI grep. But INFRA-03 could not be linted because the replacement prose legitimately names the banned pattern in "DO NOT use" comments.

## Repository layout (what landed)

```
/root/gt/nix_flake/crew/nixoser/
├── flake.nix                          # pinned nixpkgs + sops-nix (SHA-pinned)
├── hosts/ai-server/
│   ├── default.nix                    # minimum-viable NixOS config
│   └── hardware-configuration.nix     # placeholder rootfs
├── modules/
│   ├── canonical/default.nix          # options.canonical.* (Appendix A)
│   ├── secrets/default.nix            # sops.secrets.* + rotationDays
│   ├── stig-baseline/default.nix      # stub
│   ├── gpu-node/default.nix           # stub
│   ├── lan-only-network/default.nix   # stub — INFRA-01/02 go here
│   ├── audit-and-aide/default.nix     # stub
│   ├── agent-sandbox/default.nix      # stub
│   └── ai-services/default.nix        # stub — AI-01/02/06 config goes here
├── secrets/secrets.enc.yaml           # placeholder; real sops file on deploy
├── docs/
│   ├── prd/                           # 10 PRDs + MASTER-REVIEW (edited during ARCH-05/06, INFRA-03)
│   └── resolved-settings.yaml         # 29 audit rows
├── todos/                             # stack-ranked index + 3 track files
├── compliant-nix-config-vault/
│   ├── wiki/                          # compiled knowledge base (5 new articles, 2 extended)
│   └── raw/                           # 6 session notes + 11 pre-existing PRD notes
└── .github/workflows/nix-check.yml    # CI gate
```

## How to resume

1. `cd /root/gt/nix_flake/crew/nixoser`.
2. `gt prime` for gas-town role context.
3. Read this file + `todos/README.md` Progress section.
4. `bd ready` for any freshly-unblocked beads.
5. Next work: batch INFRA-01 + INFRA-02 into one feature PR (both act on `modules/lan-only-network`), then the AI-side Ollama fixes.
6. Pattern to follow: create bead, branch, edit, commit with raw note, push, `gh pr create`, verify `statusCheckRollup` directly (don't trust `gh run watch --exit-status`), merge, close bead, compile when 2–3 raw notes accumulate.

## What would make the next session smoother

- **Install `nix` locally.** Would collapse CI iterations from N to 1. Tracked informally; not a TODO yet.
- **Commit `flake.lock`.** Once `nix` is available; delete the "bootstrap if missing" step in the workflow.
- **Rotate action pins to SHAs + enable Dependabot.** Caught by lesson 26.
- **Consider promoting ARCH-17 (acceptance-criteria test harness) to P1.** Currently P2. Would enforce canonical.nix ↔ resolved-settings.yaml agreement mechanically.

## Not compile-worthy to wiki

This file is a session-specific checkpoint. Lessons have already been lifted to `wiki/review-findings/lessons-learned.md`. The session log itself stays in raw/ as a timestamped narrative — if a future session wants to understand "how did we get here?", the answer is in this file + git log.
