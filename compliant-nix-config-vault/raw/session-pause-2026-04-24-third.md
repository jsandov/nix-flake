# Session pause checkpoint — 2026-04-24 (third snapshot)

Third snapshot of the nix-flake project state in the same day. Extends `session-pause-2026-04-24.md` and `session-pause-2026-04-24-cont.md` with the post-ARCH-10 / ARCH-11 state and the build-and-test tooling research pass.

## State of main

- **33 PRs merged** on `main` cumulative. This session added 5: #47 (ARCH-10), #48 (wiki compile for ARCH-10), #49 (ARCH-11), #50 (build+test tooling research), #51 (verify pass on the research note).
- **24/68 TODOs closed** — 15 of 16 P0s (AI-04 human-gated) + 9 P1s.
- CI gate unchanged at 8 steps; every PR this session landed green (ARCH-11 took three attempts — two statix W04 fix-forwards).

## Completed this session

| PR | Bead | TODO | What shipped |
|---|---|---|---|
| #47 | — | ARCH-10 | First cross-cutting runtime service — `modules/audit-and-aide/evidence.nix`; `services.complianceEvidence.*` with `collectors` attrsOf-submodule extension point; weekly timer + `nixos-rebuild switch` activation hook; 13 default collectors + `manifest.sha256` tamper seal |
| #48 | — | (compile) | Wiki: `shared-controls/evidence-generation.md` rewritten from plan to shipped; lessons 39–42 (aggregator default.nix, extension-point options, activation+timer duality, writeShellApplication) |
| #49 | nf-4ab | ARCH-11 | `modules/accounts/default.nix` — `security.accounts.adminUser` submodule, `hashedPassword = "!"` key-only admin, first real consumer of `services.complianceEvidence.collectors` via an `accessReview` entry (snapshot of canonical auth policy + getent + ssh-keygen -lf + chage -l); retires `users.allowNoPasswordLogin` skeleton escape in `stig-baseline` |
| #50 | nf-ugb | (research) | Raw note surveying Packer / Vagrant / nixos-generators / `system.build.vm` / `runNixOSTest` / nixos-anywhere / disko; recommends dropping Packer+Vagrant for the NixOS-native stack; 7 follow-up TODOs proposed (ARCH-19..25) plus textual clarification to ARCH-17 |
| #51 | nf-ugb | (research) | Verify-pass follow-up resolving all 20 `[verify:<url>]` tags with WebFetch/WebSearch; two material corrections — nixos-generators archived 2026-01-30 (upstreamed to nixpkgs ≥25.05); nixos-anywhere has no documented Secure Boot howto |

## Patterns confirmed / introduced this session

1. **Aggregator-style `default.nix`** — `audit-and-aide/default.nix` is now `imports = [ ./auditd.nix ./evidence.nix ]; services.complianceEvidence.enable = lib.mkDefault true;`. The mkDefault lives in the aggregator, NOT inside the submodule's `config = mkIf cfg.enable { … }` (circular). Pattern will repeat for INFRA-09 AIDE as a third submodule.
2. **Extension-point options — `types.attrsOf (types.submodule { … })`** — `services.complianceEvidence.collectors` validated at scale in PR #49. Framework modules add entries under unique keys; `lib.mkForce` required to override core entries. Canonical shape for "downstream modules contribute rows to a shared pipeline."
3. **Activation-script + timer duality for compliance tasks** — ARCH-10's `systemd.timers.compliance-evidence-snapshot` (weekly, `Persistent=true`, 15-min jitter) + `system.activationScripts.complianceEvidenceOnRebuild`. Pairs auditor-facing cadence with auditd `nixos-rebuild` watch-key correlation.
4. **`pkgs.writeShellApplication` over `writeShellScript`** — ARCH-10 and ARCH-11 both use it; gets `set -euo pipefail`, shellcheck, `runtimeInputs` PATH sandbox.
5. **`mkIf` on attrset options** — PR #49's `services.complianceEvidence.collectors = mkIf cfg.accessReviewEnable { accessReview = { … }; };` was flagged by the ARCH-11 agent as a risk; eval passed on first try. Confirms the NixOS module system handles `mkIf` transparently at the attrset level.
6. **Statix W04 two-fix-forward pattern on new modules** — ARCH-11 needed two fix-forward pushes for W04 (`foo = x.foo` → `inherit (x) foo`). Normal cost for a new ~200-line module. Budget one iteration per PR; two iterations for module files with many field-level reads.

## What's next

### Open beads

- **`nf-0z4`** (P2) — README.md refresh after P1 foundation. Stale "scaffolded skeleton with stub modules" wording; missing canonical/meta/secrets/accounts modules, 8-step CI gate, evidence framework, Secure Boot, residual risks, beads as tracker. User asked to pick up after the verify pass + checkpoint.

### P0 queue (1 item)

- **AI-04** — human-gated SEV/TDX hardware decision. Unchanged.

### P1 queue (16 remaining)

In rough priority order:

- **ARCH-17** — Acceptance-criteria test harness. Now scoped to `pkgs.testers.runNixOSTest` per the tooling research. Each prd.md §10 criterion becomes a derivation under `checks.x86_64-linux.*`. Depends on ARCH-20 (disko) for the LUKS-status assertion.
- **INFRA-05** — `stig-baseline` kernel + sysctl + boot params (ARCH-09 shipped boot integrity; INFRA-05 completes the kernel hardening).
- **INFRA-06** — PAM via structured NixOS options (depends on ARCH-11 ✓).
- **INFRA-07** — SSH hardening from `canonical.ssh` (depends on ARCH-11 ✓).
- **INFRA-08** — Centralised syslog forwarding over TLS.
- **INFRA-09** — AIDE with `canonical.aidePaths`. Third submodule of `audit-and-aide`.
- **AI-08** — `agent-sandbox` with UID-per-agent.
- **AI-09** — `ai-services` (Ollama + Nginx split).
- **AI-10** — `gpu-node`; VRAM-limit blind-spot docs.
- **AI-11** — Move approval gate in-flake.
- **AI-12, AI-13** — Expand residual-risks rows.
- **AI-17** — §164.316 HIPAA policies.
- **AI-18** — rsyslog TLS (pairs with INFRA-08).
- **AI-19** — Fix AIDE alerting `$SERVICE_RESULT` issue.

### Proposed new TODOs from the research (not yet created)

If the project accepts PR #50+#51's recommendation, add to `todos/01-architecture-and-cross-cutting.md`:

- **ARCH-19** nixos-generators flake input + `packages.<system>.{iso,qcow2,vagrant-box}` (P1, M).
- **ARCH-20** disko flake input + declarative disk layout (P1, M). Blocks ARCH-17's LUKS assertion.
- **ARCH-21** nightly ISO+qcow2 build on main (P2, M).
- **ARCH-22** evidence-collector `firstBootMarker` + `activationOnly` toggle (P2, S).
- **ARCH-23** release-tag signing + GPG sub-key ceremony (P2, M).
- **ARCH-24** remote x86_64 builder ops doc for ARM devs (P3, S).
- **ARCH-25** Secure Boot first-boot enrolment runbook (P2, S). Larger than first assumed — no documented nixos-anywhere path; runtime integration work required.
- Textual clarification to **ARCH-17** — acceptance harness adopts `pkgs.testers.runNixOSTest`, PR-fast subset + nightly full matrix.

## Decisions made during this session

1. **Drop Packer and Vagrant** as first-class tooling. Adopt `nixos-generators` + `pkgs.testers.runNixOSTest` + `nixos-anywhere` + `disko`. Ship a `vagrant-virtualbox` box on demand for contributors who want one; no `Vagrantfile` in-tree. (Authority: PR #50 research note, PR #51 verify pass.)
2. **Secure Boot via "option (b)"** — ship lanzaboote pre-configured but defer sbctl key enrolment to first boot. Rejected the "bake test keys and rotate on deploy" approach (risks signed-with-test-key production on rotation skip) and the "start with systemd-boot, flip on first rebuild" approach (ships a different bootloader than production). (Authority: PR #50 research note §ARCH-09 interaction.)
3. **CI cadence tiering** — per-PR fast subset of `runNixOSTest` (+3–6 min on top of the 8-step gate); nightly full matrix + ISO + qcow2; release-only signing. Not yet implemented. (Authority: PR #50 research note §CI integration sketch.)
4. **Access-review collector runs inside the ARCH-10 snapshot service**, not on its own timer. The snapshot framework IS the cadence. Rejected a separate timer. (Authority: PR #49 raw note.)
5. **SSH public key inline in the host config**, not sops-nix. Public keys are public; the encrypt/decrypt roundtrip is friction without security value. (Authority: PR #49 raw note.)

## Open decisions still needing human input

Unchanged from prior checkpoints:

1. **AI-04** — SEV/TDX hardware path for ePHI.
2. Single-tenant declaration (encoded as meta-module default; explicit human confirmation still useful).
3. App-layer ownership — OWASP residual, EU AI Act logger, RAG governance.
4. HITRUST scope — if aspirational only, defer the 19-domain rewrite (shipped; see PR #44) to P3.
5. Quarterly review owner for ATLAS + framework-drift watch.
6. IPv6 in/out of scope.
7. Physical-access threat model.

New from this session:

8. **Signing-key ceremony for ARCH-23** — root key holder, sub-key location, revocation path.
9. **`install-iso` vs `iso`** — live media with `nixos-install` vs boot-the-configured-system. `install-iso` is conventional for bare-metal; operator preference unknown.
10. **nixos-generators → nixpkgs in-tree bump timing** — no urgency while on 24.11; decision becomes relevant at 25.05+ bump.

## Repository layout (updated)

```
/root/gt/nix_flake/crew/nixoser/
├── flake.nix                          # pinned nixpkgs + sops-nix + lanzaboote + (accounts import)
├── hosts/ai-server/                   # minimum-viable host + adminUser declaration
├── modules/
│   ├── canonical/default.nix          # Appendix A typed options (ARCH-02)
│   ├── meta/default.nix               # threat model, data classification, tenancy (ARCH-08)
│   ├── secrets/default.nix            # sops-nix (ARCH-05)
│   ├── stig-baseline/default.nix      # Secure Boot + 9 canonical reads; allowNoPasswordLogin RETIRED (ARCH-09 + ARCH-11 follow-up)
│   ├── accounts/default.nix           # NEW — admin user + access-review collector (ARCH-11)
│   ├── gpu-node/default.nix           # stub — AI-10
│   ├── lan-only-network/default.nix   # stub — INFRA-01/02 are PRD-prose; module code future
│   ├── audit-and-aide/
│   │   ├── default.nix                # aggregator — imports + mkDefault enable
│   │   ├── auditd.nix                 # REAL (INFRA-04) — auditd comprehensive
│   │   └── evidence.nix               # REAL (ARCH-10) — compliance-evidence framework
│   ├── agent-sandbox/default.nix      # stub — AI-08
│   └── ai-services/default.nix        # stub — AI-09
├── secrets/secrets.enc.yaml           # placeholder; real sops file on deploy
├── docs/
│   ├── prd/                           # 10 PRDs + MASTER-REVIEW
│   ├── resolved-settings.yaml         # 29 conflict-resolution rows
│   └── residual-risks.md              # 9 residual-risk rows (ARCH-13)
├── todos/                             # stack-ranked index + 3 track files
├── compliant-nix-config-vault/
│   ├── wiki/                          # 12+ compiled articles, 42 lessons
│   └── raw/                           # session notes including this checkpoint, ARCH-10 + ARCH-11 + build-and-test research
└── .github/workflows/nix-check.yml    # 8-step CI gate (unchanged)
```

## How to resume

1. `cd /root/gt/nix_flake/crew/nixoser`.
2. `gt prime` for gas-town role context.
3. Read this file + `todos/README.md` Progress section.
4. For the research-derived TODOs, read `compliant-nix-config-vault/raw/build-and-test-tooling-research.md` — that's the authority for ARCH-19..25 if the project accepts the recommendation.
5. `bd list --status open` to surface any open research beads.
6. **Recommended next PR after this checkpoint:** `nf-0z4` (README refresh — low-risk doc PR) or **INFRA-07** (SSH hardening from `canonical.ssh`, now unblocked by ARCH-11). ARCH-17 is the highest-value follow-up but requires ARCH-19/20 (new TODOs) to land first for LUKS assertions.
7. Multi-agent dispatch: **always `isolation: "worktree"` if >1 agent will write files concurrently**. If an agent needs WebSearch/WebFetch, dispatch WITHOUT isolation (sandbox denies web tools in worktrees) and instruct the agent to emit full content inline — this pattern worked cleanly for PR #51's verify-pass input.
8. Agent commit-path sandbox note: subagents can `git add` but not `git commit` in this environment. Have them stage and return full content; the main session commits. Returning content inline is more robust than relying on worktree file survival — PR #50's first research run lost its worktree because "no commits = no changes = auto-cleanup."

## Not compile-worthy to wiki

Session-specific checkpoint. Generalisable patterns have been lifted into `wiki/review-findings/lessons-learned.md` entries 39–42 (PR #48). New lessons worth promoting in a future compile pass:

- **Lesson 43 candidate:** Agent worktrees auto-clean when no commits land. If the sandbox blocks `git commit`, file writes in the worktree vanish with the cleanup. Always instruct agents to return final content inline in the response — the transcript is the authoritative output, the worktree is just scratch.
- **Lesson 44 candidate:** WebSearch/WebFetch are denied in agent worktrees but available in the main session. Split research agents into two modes: worktree-only for content that doesn't need the web, no-isolation + inline-output for web-enabled research.
- **Lesson 45 candidate:** Fix-forward cadence on statix W04 — budget one extra CI iteration for any new module with many field-level reads (ARCH-11 needed two).
- **Lesson 46 candidate:** Verify pass as a second-stage research contract. Draft with a sandboxed research agent, mark every version-specific claim `[verify:<url>]`, then run a web-capable pass in the main session that resolves tags and surfaces material corrections. Works; PR #50 + #51 executed this cleanly.
