# Flake Modules

The system is built as a NixOS flake with ten primary modules — four **foundation** modules that declare typed options for the cross-cutting contracts, and six **behaviour-owning** modules that consume them. Each owns a defined set of controls and can be enabled, configured, and tested independently.

## Foundation Modules

These four modules declare the shared contracts (canonical values, threat model, secrets lifecycle, operator identity). They carry typed `mkOption` declarations that every other module reads from. None of them set behaviour directly on the target system — they're the machinery the behaviour modules depend on.

### `canonical` — Cross-Framework Single Source of Truth (ARCH-02 + ARCH-04)
- Typed options for every value multiple frameworks care about: password policy, audit retention, TLS ciphers, tmpfiles rules, AIDE paths, allowed users.
- Paired with `docs/resolved-settings.yaml` — the audit-consumable projection of the same values.
- Every behaviour module reads `config.canonical.*`; no framework module redeclares these values.
- See [[../shared-controls/canonical-config]].

### `meta` — Threat Model + Data Classification + Tenancy (ARCH-08)
- `system.compliance.threatModel.{adversaries, outOfScope}` typed as an attribute set.
- Data-classification scheme (single-value enum `four-tier-public-internal-sensitive-restricted`) plus per-tier handling strings.
- Tenancy mode (`single-tenant | multi-tenant`) with a prose rationale field that becomes evidence.
- See [[meta-module]].

### `secrets` — sops-nix Integration (ARCH-05)
- Per-secret declarations under `config.sops.secrets.<name>`.
- `options.secrets.rotationDays` typed attrset: TLS 90d, API 90d, SSH/LUKS/TOTP/backup on compromise only.
- Age keys provisioned out-of-band at first boot.
- Project decision: sops-nix, not agenix. See [[../shared-controls/secrets-management]].

### `accounts` — Interactive Operator Identity (ARCH-11)
- `security.accounts.adminUser` submodule (name, description, authorizedKeys, groups).
- `hashedPassword = "!"` idiom — key-only admin login.
- Registers the quarterly-access-review collector with the ARCH-10 evidence framework — first real consumer of `services.complianceEvidence.collectors`.
- Retired the pre-ARCH-11 `users.allowNoPasswordLogin` skeleton escape.
- See [[../shared-controls/account-lifecycle]].

## Behaviour-Owning Modules

### `stig-baseline` — OS Foundation
- Kernel hardening, SSH lockdown (key-only + MFA), PAM config.
- Login banners, service minimization, Secure Boot via lanzaboote (ARCH-09).
- Consumes nine distinct values from `config.canonical.*` — the first scale validation of the canonical contract.
- See [[boot-integrity]] for the Secure Boot dormant/active priority-dance pattern.

### `audit-and-aide` — Logging, Integrity, Evidence (aggregator)
- `auditd.nix` — comprehensive kernel audit rules with NixOS-correct paths (INFRA-04; see [[../nixos-platform/auditd-module-pattern]]).
- `evidence.nix` — shared compliance-evidence framework with `services.complianceEvidence.collectors` attrset-submodule extension point (ARCH-10). Weekly timer + `nixos-rebuild switch` activation hook.
- AIDE file integrity monitoring deferred to INFRA-09 (future third submodule of this aggregator).
- `default.nix` is a thin aggregator: `imports = [ ./auditd.nix ./evidence.nix ]; services.complianceEvidence.enable = lib.mkDefault true;`
- See [[../shared-controls/evidence-generation]].

### `gpu-node` — NVIDIA/CUDA **[stub]**
- Planned: proprietary driver installation, CUDA toolkit provisioning.
- Documents necessary security exceptions — `MemoryDenyWriteExecute` incompatible with CUDA ([[../ai-security/ai-security-residual-risks]]).
- Planned: validate driver updates against hardened baseline.
- Tracked by AI-10. Ships as a comment-only stub that imports cleanly so the flake evaluates end-to-end.

### `lan-only-network` — Network Posture **[stub]**
- Planned: default-deny inbound, explicit port allowlist per interface (22, 11434, 8000).
- Planned: per-UID egress filtering via nftables, DNS restrictions, NTP sync.
- Uses nftables exclusively (NixOS 24.11 default) — never iptables `extraCommands`. INFRA-01/02 landed the PRD-side prose; module code deferred.
- Ships as a stub.

### `agent-sandbox` — AI Agent Isolation **[stub]**
- Planned: systemd security (`PrivateTmp`, `ProtectSystem=strict`, `NoNewPrivileges`, seccomp).
- Planned: tool allowlisting, human-in-the-loop approval gates, resource quotas, per-agent UID separation.
- Tracked by AI-08. Ships as a stub.

### `ai-services` — Inference Stack **[stub]**
- Planned: Ollama bound to `127.0.0.1:11434` (no direct LAN exposure); LAN access via Nginx TLS reverse proxy only.
- Planned: model registry with [[../ai-governance/model-supply-chain|provenance tracking]]; per-client rate limiting (≤30 req/min).
- Tracked by AI-09. Ships as a stub.

## Dependency Order

```
canonical ──┐
meta ───────┤
secrets ────┤   (foundation: declare options)
accounts ───┘
     │
     ▼
stig-baseline ─── (consumes canonical + accounts)
     │
     ├── audit-and-aide ─── (consumes canonical; registers collectors)
     │       └── accounts registers accessReview collector
     │
     ├── gpu-node ──────────── [stub]
     ├── lan-only-network ─── [stub]
     ├── agent-sandbox ────── [stub; will consume meta for tenancy/classification]
     └── ai-services ───────── [stub; depends on gpu-node + agent-sandbox + lan-only-network]
```

## Delivery Phases

| Phase | Modules | Status |
|---|---|---|
| 1: Foundation | canonical, meta, secrets, accounts | Complete |
| 2a: OS baseline | stig-baseline, audit-and-aide (auditd + evidence) | Complete |
| 2b: Network | lan-only-network | Stub; PRD prose landed |
| 2c: GPU | gpu-node | Stub |
| 2d: AI | agent-sandbox, ai-services | Stubs |
| 3: Validation | All + acceptance-test harness (ARCH-17) | Queued |
| 4: Hardening | All + CVE scan cadence, vulnix, LUKS acceptance | Queued |

## Key Takeaways

- Four foundation modules declare the typed contracts; six behaviour modules consume them — single source of truth enforced structurally.
- Each module maps to specific compliance control families — see [[../compliance-frameworks/cross-framework-matrix]].
- `canonical` is the project's single source of truth; no framework module redeclares values.
- `audit-and-aide` is an aggregator with real-code submodules (`auditd.nix` + `evidence.nix`); AIDE lands as a third submodule in INFRA-09.
- Four modules still ship as stubs (`gpu-node`, `lan-only-network`, `agent-sandbox`, `ai-services`) — they import cleanly so the flake evaluates, and their planned behaviour is in the track files under `todos/`.
- Module separation prevents the common failure of a monolithic compliance config.
