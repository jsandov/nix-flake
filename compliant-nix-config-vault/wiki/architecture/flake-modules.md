# Flake Modules

The system is built as a NixOS flake with six primary modules. Each owns a defined set of controls and can be enabled, configured, and tested independently.

## Module Overview

### `stig-baseline` — OS Foundation
- Kernel hardening, SSH lockdown (key-only + MFA), PAM config
- Account policies, login banners, service minimization, boot integrity
- All other modules build on this — it is the security foundation
- Owns: [[canonical-config-values]] for kernel, SSH, accounts

### `gpu-node` — NVIDIA/CUDA
- Proprietary driver installation, CUDA toolkit provisioning
- Documents necessary security exceptions
- Key exception: `MemoryDenyWriteExecute` is incompatible with CUDA — see [[ai-security-residual-risks]]
- Must validate driver updates against hardened baseline

### `lan-only-network` — Network Posture
- Default deny inbound, explicit port allowlist per interface (22, 11434, 8000)
- Per-UID egress filtering via nftables — see [[canonical-config-values]]
- DNS restrictions, NTP sync for log correlation
- Uses **nftables exclusively** (NixOS 24.11 default) — never iptables extraCommands

### `audit-and-aide` — Logging & Integrity
- auditd kernel events + journald service logs with persistent storage
- AIDE file integrity monitoring with hourly checks
- Drift detection with alerting via `OnFailure=notify-admin@`
- Automated [[../shared-controls/evidence-generation|evidence generation]] for compliance audits

### `agent-sandbox` — AI Agent Isolation
- systemd security: PrivateTmp, ProtectSystem=strict, NoNewPrivileges, seccomp
- Tool allowlisting, human-in-the-loop approval gates
- Resource quotas: MemoryMax=4G, CPUQuota=200%, TasksMax=64
- Per-agent UID separation — see [[owasp-agentic-threats]]

### `ai-services` — Inference Stack
- Ollama bound to `127.0.0.1:11434` (no direct LAN exposure)
- LAN access via Nginx TLS reverse proxy only
- Model registry with [[../ai-governance/model-supply-chain|provenance tracking]]
- Per-client rate limiting (≤30 req/min)

## Dependency Order

```
stig-baseline
  ├── gpu-node
  ├── lan-only-network
  ├── audit-and-aide
  ├── agent-sandbox
  └── ai-services
        └── (depends on gpu-node, agent-sandbox, lan-only-network)
```

## Delivery Phases

| Phase | Modules | Focus |
|---|---|---|
| 1: Foundation | stig-baseline, lan-only-network, audit-and-aide | Security baseline |
| 2a: GPU | gpu-node | Driver validation |
| 2b: AI | ai-services, agent-sandbox | Inference + agents |
| 3: Validation | All | Evidence generation |
| 4: Hardening | All | Gap analysis, perf testing |

## Key Takeaways

- Each module maps to specific compliance control families — see [[../compliance-frameworks/cross-framework-matrix]]
- The `stig-baseline` module owns all canonical NixOS options that must be set exactly once
- `ai-services` depends on three other modules — deploy foundation first
- Module separation prevents the common failure of a monolithic compliance config
