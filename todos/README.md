# nix-flake TODOs — Master Stack-Ranked Index

Source of truth for work on the compliance-mapped NixOS AI server. Derived from the 10 PRDs in `docs/prd/`, the Obsidian wiki at `compliant-nix-config-vault/`, and the gap analysis in `docs/prd/MASTER-REVIEW.md`.

## How this is organized

Work is split across three tracks that can progress semi-independently once the architecture foundation is in place:

| File | Track | Count |
|---|---|---|
| [01-architecture-and-cross-cutting.md](01-architecture-and-cross-cutting.md) | Flake skeleton, canonical config, CI, secrets, threat model, shared evidence/logging | 18 |
| [02-infrastructure-hardening.md](02-infrastructure-hardening.md) | NIST 800-53, STIG/DISA, PCI DSS — firewall, auditd, PAM, SSH, FIM, anti-malware | 22 |
| [03-ai-and-compliance.md](03-ai-and-compliance.md) | HIPAA, HITRUST, OWASP LLM, AI governance — GPU node, agent sandbox, ai-services, live-memory ePHI | 28 |

**68 TODOs total.** Each entry in the track files carries priority, effort, dependencies, and source refs back to the PRDs / wiki.

## Priority legend

- **P0** — blocks implementation start. Broken Nix, missing foundation, or decisions that ripple through everything.
- **P1** — must be done during Phase 1 (foundation modules). Without these, subsequent modules are built on sand.
- **P2** — should be done before Phase 3 wrap-up. Hardening, evidence pipelines, and compliance coverage.
- **P3** — post-Phase-3 polish, advanced hardware controls, ongoing cadence.

## Progress

_Last updated: 2026-04-24 (post-ARCH-11 account lifecycle). Update on pause or major merge._

| Priority | Done | Total |
|---|---|---|
| P0 | **15** | 16 |
| P1 | **9** | 25 |
| P2 | 0 | 18 |
| P3 | 0 | 9 |
| **All** | **24** | **68** |

Only **AI-04** remains open among P0 — blocked on human SEV/TDX decision. Every other P0 closed. Nine P1s complete: `ARCH-07` (secret-leak lint), `ARCH-08` (meta module), `ARCH-09` (Secure Boot/lanzaboote), `ARCH-10` (evidence generation framework), `ARCH-11` (account lifecycle), `ARCH-12` (RAG data flow §6.3), `ARCH-13` (residual-risks appendix), `INFRA-04` (first real module — audit-and-aide), `AI-14+15+16` (HITRUST 19-domain taxonomy).

Current state + next-slice guidance in `compliant-nix-config-vault/raw/session-pause-2026-04-24-cont.md`.

## Stack-ranked P0 list (do first)

The P0 queue is ordered by unblocking power — earlier items unblock later ones.

| # | ID | Title | Effort | Status |
|---|---|---|---|---|
| 1 | ARCH-01 | Bootstrap flake skeleton and six-module layout | M | ✓ PR #20 |
| 2 | ARCH-03 | CI: `nix flake check` + `nix eval` on every commit | S | ✓ PR #20 |
| 3 | ARCH-02 | Extract Appendix A canonical config into a single source-of-truth module | M | ✓ PR #22 |
| 4 | ARCH-04 | Resolved Settings Table as machine-readable data | S | ✓ PR #23 |
| 5 | ARCH-05 | Pick and implement a secrets module (sops-nix) | M | ✓ PR #26 (+ #27 hotfix) |
| 6 | ARCH-06 | Strip `/usr/bin`, `/sbin`, `/usr/sbin` references everywhere | S | ✓ PR #29 |
| 7 | INFRA-03 | Remove every phantom / deprecated NixOS option flagged in MASTER-REVIEW | S | ✓ PR #30 |
| 8 | INFRA-01 | Rewrite `lan-only-network` firewall to nftables with correct egress | M | ✓ PR #33 (batched w/ INFRA-02) |
| 9 | INFRA-02 | Bind all listeners (Ollama, app API, SSH) to loopback / LAN NIC | S | ✓ PR #33 |
| 10 | AI-06 | Lock `OLLAMA_HOST` to loopback and harden ai-services exposure | S | ✓ PR #36 (pre-check) |
| 11 | AI-01 | Scope `MemoryDenyWriteExecute` to non-CUDA services only | S | ✓ PR #36 (pre-check) |
| 12 | AI-02 | Remove `WatchdogSec` from Ollama, replace with external health timer | S | ✓ PR #36 (pre-check) |
| 13 | AI-03 | Fix `ai-model-fetch` for Ollama's content-addressed blob format | M | ✓ PR #36 (pre-check) |
| 14 | AI-07 | Correct `OLLAMA_NOPRUNE` framing (not a security control) | S | ✓ PR #36 (pre-check) |
| 15 | AI-05 | Disable core dumps system-wide (prevent ePHI on disk) | S | ✓ PR #36 (pre-check) |
| 16 | AI-04 | **DECISION:** disposition live-memory ePHI risk — SEV/TDX vs accepted risk | M | blocked on human |

Totals: 6 ARCH, 3 INFRA, 7 AI = 16 P0 items. **15 of 16 complete. Only AI-04 (human-gated) open.**

## P1 foundation queue

Order within P1 is flexible, but roughly:

1. **Architecture shared modules** — ARCH-07 (secrets-in-store lint), ARCH-08 (threat model in-flake), ARCH-09 (Secure Boot), ARCH-10 (evidence framework), ARCH-11 (account lifecycle), ARCH-12 (RAG data flow), ARCH-13 (residual-risk appendix)
2. **Infrastructure baseline modules** — INFRA-04 (auditd NixOS paths), INFRA-05 (`stig-baseline`), INFRA-06 (PAM), INFRA-07 (SSH), INFRA-08 (TLS syslog), INFRA-09 (AIDE)
3. **AI modules & compliance gaps** — AI-08 (`agent-sandbox`), AI-09 (`ai-services`), AI-10 (`gpu-node`), AI-11 (approval gate in-flake), AI-12/13 (OWASP/HIPAA residual-risk), AI-14/15/16 (HITRUST taxonomy + maturity fixes + missing domains), AI-17 (§164.316 policies), AI-18 (rsyslog TLS), AI-19 (AIDE alerting)

## P2 and P3

See track files for details. P2 is hardening and coverage (anti-malware, mount opts, TLS ciphers, vuln scanning plan, RAG governance, EU AI Act logger). P3 is advanced hardware (Secure Boot, FIPS provider, Thunderbolt DMA, usbguard) and ongoing cadence (quarterly ATLAS review, framework version drift).

## Cross-track dependency contract

Everything below is enforced structurally by the ARCH track. Infra and AI tracks **reference, not redeclare**:

- **ARCH-02 canonical config** is the single source for log retention, SSH ciphers, password policy, firewall CIDRs, sysctl values. No infra/AI TODO should hardcode these.
- **ARCH-03 CI gate** will reject any PR whose flake doesn't evaluate. Expect early infra PRs to surface most of the 17+ broken snippets from MASTER-REVIEW Systemic Issue #2.
- **ARCH-05 sops-nix** is the only path for secrets. Infra (INFRA-08 syslog TLS) and AI (AI-18 rsyslog TLS, AI-22 Article 12 logger) consume `config.sops.secrets.*`.
- **ARCH-10 evidence framework** is the shared systemd timer. Infra (INFRA-17) and AI (AI-28) add control-specific artifacts; no parallel collectors.
- **ARCH-13 residual-risk appendix** is where HIPAA live-memory (AI-13), OWASP application-layer gaps (AI-12), and model-provenance honesty (AI-03) land their "infrastructure can't solve this" statements.
- **ARCH-16 boundary lints** enforce single ownership of `boot.blacklistedKernelModules`, `sysctl`, `tmpfiles.rules`, firewall, PAM `.text`. Infra track owns declarations; AI track references.

## Open decisions needed from the human

Before P0 items 10–16 can fully land, the following need answers:

1. **AI-04 — Target hardware path for ePHI.** Does deployment support AMD SEV-SNP or Intel TDX? A workstation with consumer NVIDIA forces the "signed risk-acceptance letter" path, which ripples into HIPAA §164.308(a)(1)(ii)(B), HITRUST privacy domain, and EU AI Act high-risk classification.
2. **ARCH-08 — Single-tenant declaration.** Master PRD review flagged this as missing. Confirm single-operator before AI-26 tiered guide is finalized.
3. **App-layer ownership.** OWASP residual-risk (AI-12), Article 12 logger (AI-22), and RAG governance (AI-20) assume someone will eventually write the port-8000 orchestrator. If there is no app-layer team, the "aspirational" fraction grows from ~60% to ~100% and must be declared on the tin.
4. **HITRUST scope.** AI-14/15/16 assume an actual HITRUST assessment. If aspirational only, defer the 19-domain rewrite and drop the L5-maturity cleanup to P3.
5. **Quarterly review owner.** ATLAS refresh (AI-21 / AI-27) and framework version drift (ARCH-18) need a named human or a beads-assigned agent.
6. **IPv6 in/out of scope?** INFRA-01 firewall decision — the PRDs are inconsistent.
7. **Physical access in threat model?** Gates INFRA-18 (Secure Boot) and INFRA-20 (Thunderbolt DMA). Master PRD threat model is missing per review.

## Conventions

- IDs are stable. Once assigned, never renumber. New items get the next integer.
- When a TODO ships, move it to a `done/` section within its track file rather than deleting.
- When splitting a TODO, the parent keeps its ID and new children get suffixes (`AI-09a`, `AI-09b`).
- If you want these mirrored into beads for assignment/tracking: `bd create --title "<ID>: <title>" --description "<description>" --type=task --priority=<0-3>` — these markdown files remain the source of truth; beads are the work queue.
