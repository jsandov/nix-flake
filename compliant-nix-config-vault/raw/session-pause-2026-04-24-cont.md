# Session pause checkpoint — 2026-04-24 (continued)

Second snapshot of the nix-flake project state in the same session. Extends `session-pause-2026-04-24.md` with the post-P1 state. A fresh session can read this + `todos/README.md` Progress and orient in under five minutes.

## State of main

- 28 PRs merged on `main`. Last: PR #45 (wiki compile for INFRA-04 + ARCH-09 + ARCH-12 + HITRUST + multi-agent lessons).
- **22/68 TODOs closed** — 15 of 16 P0s (only AI-04 remaining) + 7 P1s.
- CI gate has 8 lints now: `nix flake check`, `nix eval` toplevel, statix, deadnix, broad FHS path (code), narrow FHS path (docs audit-rule syntax), secrets-in-store (3 heuristic patterns).

## Completed since the first pause checkpoint

Landed since `session-pause-2026-04-24.md`:

| PR | TODO | What shipped |
|---|---|---|
| #33 | INFRA-01 + INFRA-02 (batched) | iptables→nftables in NIST/HIPAA/STIG PRD snippets; Nginx bound to `<LAN_INTERFACE_IP>` not `0.0.0.0` |
| #36 | AI-01/02/03/05/06/07 (pre-check audit) | All six satisfied by earlier sweeps — closed as zero-line PRs |
| #37 | ARCH-07 | Secrets-in-store leakage lint (3 heuristics) |
| #38 | ARCH-08 | Meta module — threat model + data classification + tenancy as typed options |
| #39 | ARCH-13 | Residual-risks appendix (`docs/residual-risks.md`, 9 rows) |
| #40 | (compile) | Wiki: meta-module + residual-risks-register articles, lessons 32–34 |
| #41 | INFRA-04 | **First real module code** — `audit-and-aide` with comprehensive auditd rules |
| #42 | ARCH-09 | Secure Boot via lanzaboote; stig-baseline consuming 9 canonical values |
| #43 | ARCH-12 | RAG ingestion/retrieval flow in master PRD §6.3 |
| #44 | AI-14+15+16 | HITRUST CSF v11 19-domain taxonomy + Year-1 maturity cap + 4 missing domains |
| #45 | (compile) | Wiki: auditd-module-pattern + boot-integrity articles, gotchas 17–18, lessons 35–38 |

## What's next

**P0 queue (1 item):**
- **AI-04** — Human-gated SEV/TDX hardware decision. Blocker: operator confirms whether target hardware supports AMD SEV-SNP or Intel TDX. Consumer NVIDIA forces the signed-risk-acceptance path. See `docs/residual-risks.md` row 1 for the full framing.

**P1 queue (18 remaining):**

In rough priority order:

- **ARCH-10** — Evidence generation framework. Shared systemd timer + activation script snapshotting canonical + meta + (future) evidence from framework modules. Consumed by future HITRUST/PCI evidence dumps.
- **ARCH-11** — Account lifecycle module. Declares admin user + SSH keys + rotation policy. **Retires the `users.allowNoPasswordLogin = lib.mkDefault true` skeleton escape hatch.** Required before any real deployment.
- **INFRA-05** — Build `stig-baseline` as full owner of kernel + sysctl + boot params. ARCH-09 shipped the canonical-consumption pattern; INFRA-05 adds the remaining kernel hardening (sysctl flags, kernel params, boot.kernelParams).
- **INFRA-06** — PAM configuration via structured NixOS options (no `environment.etc."login.defs"` overrides per gotcha #16). Depends on `security.loginDefs.settings` landing in canonical or ARCH-11 account lifecycle.
- **INFRA-07** — SSH hardening from `canonical.ssh` — `services.openssh.settings.*` consuming `canonical.ssh.{ciphers,macs,kexAlgorithms,...}`.
- **INFRA-08** — Centralised syslog forwarding over TLS (rsyslog + RELP or journald remote).
- **INFRA-09** — AIDE with NixOS-correct paths from `canonical.aidePaths`; hourly timer + notify-admin@ alerting.
- **AI-08** — `agent-sandbox` module with UID-per-agent allocation.
- **AI-09** — `ai-services` module (Ollama + Nginx reverse proxy split).
- **AI-10** — `gpu-node` module; VRAM-limit blind-spot documentation.
- **AI-11** — Move approval gate inside Nix-managed boundary (out of `/opt/ai/`).
- **AI-12, AI-13** — Expand residual-risks rows 2 (OWASP prompt injection) and 1+5+6 (HIPAA-specific).
- **AI-17** — §164.316 HIPAA policies + Privacy Rule individual-rights procedures.
- **AI-18** — rsyslog TLS for ePHI log transport (pairs with INFRA-08).
- **AI-19** — Fix AIDE alerting so `$SERVICE_RESULT` is actually available.

## Patterns confirmed during this batch

1. **Pre-check TODOs with grep before claiming** (lesson 29) paid off at scale — AI-01/02/03/05/06/07 were all pre-check-satisfied by earlier sweeps. Six zero-line PRs via one audit commit.
2. **Single-value enums declare intent** (lesson 32) — the pattern showed up again in meta-module's `dataClassification.scheme` and `firewall.backend`.
3. **Canonical proves out on first scale consumer** (lesson 36) — `stig-baseline` reads 9 distinct values. The `types.submodule` design from ARCH-02 held under real consumption.
4. **Gate hardware-requiring features behind an opt-in enable** — ARCH-09's `security.secureBoot.enable = false` default lets CI eval without sbctl keys. Pattern transfers to future TDX/SEV work (AI-04) and any hardware-gated control.
5. **Subagent sandbox blocks git push / gh** (lesson 37) — the three-agent parallel dispatch had to be untangled by the main session. Next multi-agent batch must set `isolation: "worktree"`.
6. **Lints catch what prose conventions don't** — CI iteration 2 on ARCH-09 caught statix W20 (repeated `boot.*` keys) + W04 (`pkiBundle = cfg.pkiBundle` vs `inherit (cfg) pkiBundle`). Style rules I wouldn't have applied on first write.

## Open decisions still needing human input

Unchanged from `session-pause-2026-04-24.md`:

1. **AI-04** — SEV/TDX hardware path for ePHI.
2. Single-tenant declaration (now encoded as default in meta module; explicit human confirmation still useful).
3. App-layer ownership — OWASP residual, EU AI Act logger, RAG governance.
4. HITRUST scope — if aspirational only, defer the 19-domain rewrite (already landed; see PR #44) to P3. The PR notes the verification caveat.
5. Quarterly review owner for ATLAS + framework-drift watch.
6. IPv6 in/out of scope.
7. Physical-access threat model.

## Repository layout (updated)

```
/root/gt/nix_flake/crew/nixoser/
├── flake.nix                          # pinned nixpkgs + sops-nix + lanzaboote (all SHA-pinned)
├── hosts/ai-server/                   # minimum-viable host
├── modules/
│   ├── canonical/default.nix          # Appendix A typed options
│   ├── meta/default.nix               # threat model, data classification, tenancy (ARCH-08)
│   ├── secrets/default.nix            # sops-nix (ARCH-05)
│   ├── stig-baseline/default.nix      # Secure Boot + 9 canonical reads (ARCH-09)
│   ├── gpu-node/default.nix           # stub — AI-10
│   ├── lan-only-network/default.nix   # stub — INFRA-01/02 are PRD-prose; module code future
│   ├── audit-and-aide/default.nix     # REAL — auditd comprehensive (INFRA-04); AIDE pending (INFRA-09)
│   ├── agent-sandbox/default.nix      # stub — AI-08
│   └── ai-services/default.nix        # stub — AI-09
├── secrets/secrets.enc.yaml           # placeholder; real sops file on deploy
├── docs/
│   ├── prd/                           # 10 PRDs + MASTER-REVIEW
│   ├── resolved-settings.yaml         # 29 conflict-resolution rows
│   └── residual-risks.md              # 9 residual-risk rows (ARCH-13)
├── todos/                             # stack-ranked index + 3 track files
├── compliant-nix-config-vault/
│   ├── wiki/                          # 12 compiled articles, 18 gotchas, 38 lessons
│   └── raw/                           # 13 session notes + 11 pre-existing PRD notes
└── .github/workflows/nix-check.yml    # 8-step CI gate
```

## How to resume

1. `cd /root/gt/nix_flake/crew/nixoser`.
2. `gt prime` for gas-town role context.
3. Read this file + `todos/README.md` Progress section.
4. `bd ready` for freshly-unblocked beads.
5. **Recommended next PR:** `ARCH-10` (evidence generation) — consumes canonical + meta + secrets rotation-days + auditd output. Natural capstone for the P1-foundation batch. Alternative: `ARCH-11` (account lifecycle) to retire the `allowNoPasswordLogin` skeleton escape.
6. When spawning multi-agent parallel work: **always set `isolation: "worktree"` on the `Agent` tool dispatch.** Today's session burned ~20 min untangling a three-agent collision.

## Not compile-worthy to wiki

This file is a session-specific checkpoint. Generalisable patterns have been lifted into `wiki/review-findings/lessons-learned.md` entries 35–38. The session log stays in raw/ as a timestamped narrative.
