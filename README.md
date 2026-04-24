# Compliant NixOS AI Server

A compliance-mapped NixOS flake for a LAN-only, hardened AI server with local GPU inference and sandboxed agentic workflows. Every technically-enforceable control from 10 regulatory and security frameworks is implemented declaratively through NixOS modules, backed by a canonical configuration contract and an 8-step CI gate.

## Status

Phase 1 foundation + early Phase 2 module work per the master PRD. See [`todos/README.md`](todos/README.md) for live Progress numbers — do not trust hard-coded counts elsewhere, they drift.

**Modules with real code landed:**

- `modules/canonical/` — typed single-source-of-truth for cross-framework values (ARCH-02)
- `modules/meta/` — threat model, data classification, tenancy (ARCH-08)
- `modules/secrets/` — sops-nix integration (ARCH-05)
- `modules/stig-baseline/` — Secure Boot via lanzaboote + 9 canonical reads (ARCH-09)
- `modules/audit-and-aide/auditd.nix` — comprehensive auditd rules with NixOS-correct paths (INFRA-04)
- `modules/audit-and-aide/evidence.nix` — shared compliance evidence framework (ARCH-10)
- `modules/accounts/` — declarative admin user + access-review evidence collector (ARCH-11)

**Modules still stubs (scaffolded, import cleanly, no real behaviour yet):**

- `modules/gpu-node/` — GPU node with VRAM limits (AI-10)
- `modules/lan-only-network/` — nftables firewall + LAN-scoped binds (INFRA-01/02 prose already in PRD; module code future)
- `modules/agent-sandbox/` — UID-per-agent isolation (AI-08)
- `modules/ai-services/` — Ollama + Nginx reverse proxy split (AI-09)

## Repository Structure

```
nix-flake/
├── flake.nix                           # pinned inputs: nixpkgs 24.11 + sops-nix + lanzaboote
├── flake.lock                          # CI-generated on first run
├── hosts/
│   └── ai-server/
│       ├── default.nix                 # host config + admin user declaration
│       └── hardware-configuration.nix  # placeholder
├── modules/
│   ├── canonical/default.nix           # Appendix A typed options (ARCH-02)
│   ├── meta/default.nix                # threat model / data class / tenancy (ARCH-08)
│   ├── secrets/default.nix             # sops-nix declarations (ARCH-05)
│   ├── stig-baseline/default.nix       # Secure Boot + kernel hardening (ARCH-09)
│   ├── accounts/default.nix            # admin user + access-review collector (ARCH-11)
│   ├── audit-and-aide/
│   │   ├── default.nix                 # aggregator
│   │   ├── auditd.nix                  # audit rules (INFRA-04)
│   │   └── evidence.nix                # compliance-evidence framework (ARCH-10)
│   ├── gpu-node/default.nix            # stub — AI-10
│   ├── lan-only-network/default.nix    # stub — INFRA-01/02 module code
│   ├── agent-sandbox/default.nix       # stub — AI-08
│   └── ai-services/default.nix         # stub — AI-09
├── secrets/
│   └── secrets.enc.yaml                # sops placeholder; real file on deploy
├── docs/
│   ├── prd/                            # 10 PRDs + MASTER-REVIEW.md
│   ├── resolved-settings.yaml          # audit-consumable conflict-resolution table (ARCH-04)
│   └── residual-risks.md               # what infrastructure cannot solve (ARCH-13)
├── todos/
│   ├── README.md                       # Progress + priority legend
│   ├── 01-architecture-and-cross-cutting.md
│   ├── 02-infrastructure-hardening.md
│   └── 03-ai-and-compliance.md
├── compliant-nix-config-vault/         # Obsidian knowledge base wiki
│   ├── CLAUDE.md                       # wiki conventions (compile/query/audit)
│   ├── raw/                            # source material + session notes
│   ├── wiki/                           # LLM-maintained structured articles
│   │   ├── _master-index.md            # entry point
│   │   ├── architecture/
│   │   ├── compliance-frameworks/
│   │   ├── nixos-platform/
│   │   ├── hipaa/
│   │   ├── pci-dss/
│   │   ├── ai-security/
│   │   ├── ai-governance/
│   │   ├── shared-controls/
│   │   └── review-findings/
│   └── output/                         # query results (gitignored)
└── .github/workflows/
    └── nix-check.yml                   # 8-step CI gate (ARCH-03 + lint family)
```

## How It Fits Together

**PRDs** (`docs/prd/`) define the requirements — what controls are needed, which frameworks demand them, and the resolved canonical configuration values. Start with `prd.md` for the architecture, then `MASTER-REVIEW.md` for the gap analysis that drove the TODO list.

**Wiki** (`compliant-nix-config-vault/`) is a compiled knowledge base built from the PRDs and session notes. Each cross-cutting pattern (canonical config, evidence generation, secrets, residual risks, NixOS gotchas, lessons learned) lives as a structured article with `[[wiki links]]`. Open in [Obsidian](https://obsidian.md) for the graph view, or read the markdown directly. Entry point: `wiki/_master-index.md`.

**Flake** (`flake.nix`, `modules/`, `hosts/ai-server/`) is the executable artifact. The canonical / meta / secrets / stig-baseline / audit-and-aide / accounts modules carry real behaviour; the gpu-node / lan-only-network / agent-sandbox / ai-services modules are still stubs pending their respective TODOs. All modules import cleanly so the flake evaluates end-to-end on every commit.

**Tracker** is split: the 68-item TODO queue lives in [`todos/`](todos/README.md); cross-cutting work items and research beads live in [beads](https://github.com/dandavison/beads) (see "Issue Tracking" below).

## Canonical Configuration Contract

`modules/canonical/default.nix` is the typed single source of truth for every value that multiple frameworks care about — password policy, audit retention, encryption ciphers, allowed users, TLS settings, kernel hardening flags. Framework modules **read** these values (`config.canonical.auth.passwordMinLength`, `config.canonical.encryption.tlsMinVersion`, …); they do not redeclare them. The resolved-settings table in `docs/resolved-settings.yaml` is the audit-consumable projection of the same values, regenerated when canonical changes.

This contract is what lets "strictest applicable across HITRUST / PCI / HIPAA / NIST" be a real number instead of a principle. It also enforces the ARCH-16 module-boundary rule: each option is declared by exactly one module.

See [`compliant-nix-config-vault/wiki/shared-controls/canonical-config.md`](compliant-nix-config-vault/wiki/shared-controls/canonical-config.md).

## Secrets and Boot Integrity

**Secrets (ARCH-05).** `modules/secrets/default.nix` wires sops-nix; every secret is declared via `config.sops.secrets.<name>` and consumed by reference — no plaintext in the Nix store. Age keys are provisioned to the host out-of-band at bring-up. `options.secrets.rotationDays` declares per-category cadence: TLS 90 days (PCI), API tokens 90 days, SSH/LUKS/TOTP/backup on compromise only. `agenix` was evaluated and rejected — see `compliant-nix-config-vault/wiki/shared-controls/secrets-management.md`.

**Boot integrity (ARCH-09).** `lanzaboote` is a flake input pinned by commit SHA. `security.secureBoot.enable` is gated behind an opt-in (default `false`) so CI passes without sbctl keys. Operational stance per the build-and-test research: ship the image with lanzaboote pre-configured but defer sbctl key enrolment to first boot (`sbctl create-keys && sbctl enroll-keys --microsoft && nixos-rebuild switch`). See [`compliant-nix-config-vault/wiki/architecture/boot-integrity.md`](compliant-nix-config-vault/wiki/architecture/boot-integrity.md) and [`raw/build-and-test-tooling-research.md`](compliant-nix-config-vault/raw/build-and-test-tooling-research.md) for the rationale.

## Evidence Generation

ARCH-10 ships `services.complianceEvidence.*` — a shared snapshotter wired through a weekly systemd timer and a `nixos-rebuild switch` activation hook. A snapshot is a timestamped directory under `/var/lib/compliance-evidence/` containing 13 default collectors (getent, nftables ruleset, auditctl, store closure, sshd -T, cryptsetup, nix-store --verify, flake metadata, …) plus a `manifest.sha256` tamper seal. The on-rebuild hook correlates each snapshot with the auditd `nixos-rebuild` watch key from INFRA-04.

`services.complianceEvidence.collectors` is an `attrsOf (submodule { description, command, outputFile })` — the extension point. Framework modules (HIPAA, PCI, HITRUST, access-review) register their own entries under unique keys rather than editing the shared module. The first real downstream consumer is `modules/accounts/` ARCH-11, which registers an `accessReview` collector emitting admin inventory + SSH key fingerprints + `chage -l` + a snapshot of the canonical auth policy in force.

See [`compliant-nix-config-vault/wiki/shared-controls/evidence-generation.md`](compliant-nix-config-vault/wiki/shared-controls/evidence-generation.md).

## CI Gate

`.github/workflows/nix-check.yml` runs 8 steps on every PR and push to `main`, typically 1–3 minutes wall-clock:

| # | Step | Purpose |
|---|---|---|
| 1 | `nix flake check` | Evaluates flake outputs, runs `checks.*` |
| 2 | `nix eval` toplevel `drvPath` | Walks the `ai-server` module tree end-to-end without realising any derivation |
| 3 | `statix check` | Nix anti-pattern lint (W04 inherit-from-assignment, W20 repeated keys, …) |
| 4 | `deadnix --fail` | Unused-binding detector |
| 5 | Broad FHS path lint | Blocks `/usr/bin`, `/usr/sbin`, `/sbin` in `modules/` and `hosts/` (ARCH-06) |
| 6 | Narrow FHS path lint (docs) | Matches only quoted audit-rule syntax referencing FHS paths in `docs/` |
| 7 | Secrets-in-Nix-store lint | Three heuristics: PEM in `writeText`/`toFile`, 40+ hex in `writeText`/`toFile`, literal-value secret-named env var (ARCH-07) |
| 8 | `flake.lock` generation fallback | CI generates the lock on first run when the skeleton ships without one |

Green CI is merge-gate. See [`compliant-nix-config-vault/wiki/architecture/ci-gate.md`](compliant-nix-config-vault/wiki/architecture/ci-gate.md) for the lint-vs-sweep rule and iteration budget.

## Residual Risks

[`docs/residual-risks.md`](docs/residual-risks.md) enumerates every control this flake cannot fully enforce: live-memory ePHI in RAM/VRAM (AMD SEV / Intel TDX not assumed), GPU VRAM residue post-inference, prompt injection (application layer), cgroups cannot limit VRAM, Ollama watchdog unsupported, model provenance is trust-on-first-download, semantic attacks on LLM outputs, kernel exploits bypassing systemd sandbox. Each row names its driving framework and the compensating control or accepted-risk stance. Referenced from every framework module so reviewers do not get false confidence (ARCH-13).

## Compliance Targets

| Framework | Scope |
|---|---|
| NIST SP 800-53 Rev 5 | All 20 control families (Moderate baseline) |
| HIPAA | Security Rule, Privacy Rule, Breach Notification |
| HITRUST CSF v11 | 19-domain taxonomy (AI-14/15/16) |
| PCI DSS v4.0 | All 12 requirements |
| OWASP Top 10 for LLMs | LLM + agentic AI threats |
| NIST AI RMF | Govern, Map, Measure, Manage |
| EU AI Act | High-risk AI system requirements |
| ISO 42001 | AI management system controls |
| MITRE ATLAS | Adversarial threat landscape for AI |
| STIG / DISA | NixOS hardening expectations |

## Issue Tracking

**TODO queue.** The 68-item implementation stack lives in [`todos/`](todos/README.md) across three track files: architecture / infrastructure / AI-and-compliance. Work is prioritised P0–P3; P0 blocks implementation start, P1 is the Phase 1 foundation, P2 is pre-Phase-3 hardening, P3 is polish. Every entry carries effort, dependencies, and source refs back to the PRDs and wiki. This queue is the canonical work backlog — check it before opening new work.

**Beads.** Cross-cutting work items, research tasks, and operational beads are tracked with [beads](https://github.com/dandavison/beads). The repo prefix is `nf-`. Common commands:

```
bd list --status open                          # open beads for this repo
bd create "<title>" -t task -p 1 --description "..." --acceptance "..."
bd update <id> --external-ref gh-<pr>           # link to a PR
bd update <id> --status closed
```

Beads and the TODO queue are complementary — the TODO queue is not mirrored into beads. Use beads for work that does not fit the track-file structure (research, docs, ops).

## Wiki Workflow

The knowledge base follows the [Obsidian RAG pattern](https://x.com/karpathy/status/1914026357498794388) — no vector database, no embeddings, just structured markdown with indexed navigation.

| Verb | What It Does |
|---|---|
| **Clip** | Drop source material into `raw/` (via Obsidian Web Clipper or manually) |
| **Compile** | Process `raw/` into structured wiki articles with cross-links |
| **Query** | Ask questions — navigates `_master-index.md` → topic `_index.md` → articles |
| **Audit** | Review wiki for inconsistencies, broken links, gaps |

See [`compliant-nix-config-vault/CLAUDE.md`](compliant-nix-config-vault/CLAUDE.md) for full conventions.

## Contributing

- **One TODO per PR.** Granular PRs clear CI faster and review more cleanly. Exception: two TODOs acting on the same file regions may batch.
- **Title prefixes.** `feat(<id>):` for new features; `fix(<id>):` for bug fixes; `docs(wiki):` for wiki compiles; `docs(research):` for raw-note research; `docs(<scope>):` for other documentation.
- **Wiki compiles are doc-only.** No code in compile PRs.
- **CI must be green before merge.** Always verify via `gh pr view <n> --json mergeStateStatus,statusCheckRollup` — `gh run watch --exit-status` has produced false positives in this repo.
- **No local `nix`** in many dev environments. CI is the evaluator. Budget ≥1 CI iteration per non-trivial module PR; new modules often need a statix W04 fix-forward for `foo = x.foo` → `inherit (x) foo`.
