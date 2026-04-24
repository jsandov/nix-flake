# Roadmap — post P1 foundation (2026-04-24)

Not wiki-worthy. This is a dated planning note; the live queue lives in `todos/`.

## Where we are

- **33 PRs on main**; this session alone added 12 (#47 – #58).
- **P0:** 15 of 16 — only AI-04 remains (human-gated SEV/TDX hardware decision).
- **P1:** 9 of 25 — ARCH-07/08/09/10/11/12/13, INFRA-04, AI-14+15+16.
- **Foundation contract is proven:** `canonical` declares, `stig-baseline` reads 9 values, `accounts` reads the auth subtree; `meta` declares threat/classification/tenancy; `secrets` declares sops-nix lifecycle.
- **Evidence framework is live:** `services.complianceEvidence.*` with `accessReview` as first downstream collector.
- **Build-and-test strategy decided** (PR #50 + verify pass #51): drop Packer/Vagrant; adopt `nixos-generators` + `pkgs.testers.runNixOSTest` + `nixos-anywhere` + `disko`. Seven follow-up TODOs proposed (ARCH-19 – ARCH-25), not yet created in the track file.

## P1 queue — 16 items remaining

Organised by blocker class.

### Unblocked now (pick any)

- **INFRA-05** — stig-baseline owns kernel + sysctl + boot params. Extends an existing real module; consumes more of `canonical.*` (sysctl flags, kernel params). Effort: M.
- **INFRA-06** — PAM via structured NixOS options. Unblocked by ARCH-11 (accounts). Effort: M.
- **INFRA-07** — SSH hardening from `canonical.ssh.*`. Second scale consumer of canonical after stig-baseline. Effort: S.
- **INFRA-09** — AIDE as a third submodule of `audit-and-aide/`. Uses the aggregator pattern the session just proved out. Registers a file-integrity collector with ARCH-10. Effort: M.
- **AI-08** — `agent-sandbox` with UID-per-agent. Will consume `meta.dataClassification` + `meta.tenancy`. Effort: M.
- **AI-09** — `ai-services` (Ollama + Nginx reverse proxy split). Effort: M.
- **AI-10** — `gpu-node`. Effort: M.
- **AI-11** — move approval gate in-flake (from `/opt/ai/`). Effort: S.
- **AI-12, AI-13** — expand residual-risks rows. Effort: S.
- **AI-17** — §164.316 HIPAA policies + Privacy-Rule individual-rights procedures. Effort: M.
- **AI-18** — rsyslog TLS for ePHI log transport (pairs with INFRA-08). Effort: M.
- **AI-19** — fix AIDE alerting so `$SERVICE_RESULT` is actually available. Depends on AIDE shipping (INFRA-09). Effort: S.

### Blocked

- **INFRA-08** — centralised syslog forwarding over TLS. Has an open decision (local journald vs central collector) that the research note flagged. Do not claim until the decision is made.
- **ARCH-17** — acceptance-test harness. Blocked by ARCH-19 (nixos-generators) + ARCH-20 (disko) — neither exists as a TODO yet.

### Proposed but not yet created as TODOs

From `raw/build-and-test-tooling-research.md` (post-verify-pass). If the project accepts, these go into `todos/01-architecture-and-cross-cutting.md`:

- **ARCH-19** — `nixos-generators` flake input + `packages.<system>.{iso,qcow2,vagrant-box}`. P1, M.
- **ARCH-20** — `disko` flake input + declarative disk layout. P1, M. Blocks ARCH-17's LUKS assertion.
- **ARCH-21** — nightly ISO + qcow2 build on `main`. P2, M.
- **ARCH-22** — evidence-collector `firstBootMarker` + `activationOnly` toggle. P2, S.
- **ARCH-23** — release-tag signing + GPG sub-key ceremony. P2, M.
- **ARCH-24** — remote x86_64 builder ops doc for ARM developers. P3, S.
- **ARCH-25** — Secure Boot first-boot enrolment runbook. P2, S. Larger than first assumed — `nixos-anywhere` has no documented SB path as of v1.13.0.

Plus a textual clarification to existing **ARCH-17** — acceptance harness adopts `pkgs.testers.runNixOSTest`, PR-fast subset + nightly full matrix.

## Three most-recommended next slices

In preference order; each is self-contained so the session can stop cleanly after any of them.

### 1. INFRA-09 (AIDE) — ~1-2 hrs

- Natural next feature. Aggregator pattern is proved; AIDE slots in as `audit-and-aide/aide.nix` alongside `auditd.nix` + `evidence.nix`.
- Consumes `canonical.aidePaths` (already declared and typed).
- Registers an `aideDaily` (or similar) collector with `services.complianceEvidence.collectors` — second real downstream consumer after `accounts.accessReview`.
- Uses `pkgs.writeShellApplication` + `notify-admin@` (patterns established).
- Control coverage: NIST SI-7, PCI 11, HIPAA §164.312(b).
- Follow-up AI-19 (fix `$SERVICE_RESULT`) becomes trivial once AIDE is shipping.

### 2. Create ARCH-19..25 TODO entries — ~15 min

- Single edit to `todos/01-architecture-and-cross-cutting.md` per proposed TODO.
- Unblocks ARCH-17 once ARCH-19 + ARCH-20 exist as actual tickets.
- Converts the research-note recommendations into scheduled work. Low-risk, high-strategic-value.
- Good palate cleanser.

### 3. INFRA-07 (SSH hardening from `canonical.ssh.*`) — ~30 min

- Second scale consumer of canonical on a real module.
- Small scope, clear boundaries. Moves one more stub to real code.
- Validates `canonical.ssh.{ciphers, macs, kexAlgorithms, …}` contract.

## Risks / notes

- **AI-side stubs** (`gpu-node`, `agent-sandbox`, `ai-services`) are still all stubs. Breaking ground on any of them is higher variance — GPU driver decisions, systemd sandbox exceptions for CUDA (see lesson #5), Ollama content-addressed-blob gotcha (#7). Prefer infrastructure P1s (INFRA-*) unless the project is ready for the AI-side scope.
- **Evidence framework on synthetic images** (ARCH-22) carries an open design question flagged in the tooling-research: first-boot snapshot vs rebuild-snapshot duality. Fine to defer.
- **Secure Boot enrolment** (ARCH-25) needs original integration work — nixos-anywhere has no documented path. Budget for a bigger bite.

## How to resume

1. Read `compliant-nix-config-vault/raw/session-pause-2026-04-24-third.md` for session state.
2. Read this note for the P1-queue landscape and trade-offs.
3. Decide between the three candidate next slices above (or pick anything else from "Unblocked now").
4. If doing INFRA-09, the first file to read is `modules/audit-and-aide/default.nix` (aggregator layout) + `modules/canonical/default.nix` (`aidePaths` at the relevant offset) + `modules/audit-and-aide/evidence.nix` (collector shape to match).
5. If doing ARCH-19..25 creation, the source of truth for entry content is `wiki/architecture/build-and-test-strategy.md` and `raw/build-and-test-tooling-research.md` — the recommendation + rationale are already compiled.
