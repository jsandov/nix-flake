# PRD Architecture Overview — NixOS Compliance-Mapped AI Server

Source: prd.md (master PRD)

## What This Is

A LAN-only, hardened NixOS-based AI server for local GPU inference and agentic workflows. Compliance-mapped from inception — every technically-enforceable control from 10 regulatory/security frameworks is implemented declaratively through NixOS flake modules.

The goal is **compliance as an engineering deliverable**, not a governance exercise.

## The Six Flake Modules

### 1. `stig-baseline` — OS Foundation
- Kernel hardening, SSH lockdown, PAM config, account policies
- Login banners, service minimization, boot integrity
- Key-only SSH with MFA (TOTP via google-authenticator)
- All other modules build on this

### 2. `gpu-node` — NVIDIA/CUDA
- Proprietary driver installation, CUDA toolkit
- Balances driver requirements against hardened profile
- Documents necessary security exceptions (e.g., MemoryDenyWriteExecute incompatible with CUDA)

### 3. `lan-only-network` — Network Posture
- Inbound restricted to approved interfaces/subnets
- Explicit port allowlisting (22, 11434, 8000)
- Egress filtering to prevent unauthorized outbound
- DNS restrictions, NTP sync

### 4. `audit-and-aide` — Logging & Integrity
- auditd rules, journald persistence, log rotation
- AIDE file integrity monitoring with scheduled checks
- Drift detection with alerting
- Automated evidence generation for compliance audits

### 5. `agent-sandbox` — AI Agent Isolation
- systemd security directives (PrivateTmp, ProtectSystem, NoNewPrivileges, namespace isolation, seccomp)
- Tool allowlisting, human-in-the-loop approval gates
- Resource quotas (CPU, memory, file descriptors)
- Network access restrictions per agent

### 6. `ai-services` — Inference Stack
- Ollama service config, inference API endpoints
- Model registry with provenance tracking
- Per-client rate limiting, TLS termination
- Input/output logging, prompt injection mitigations

## Module Dependency Order

```
stig-baseline
  ├── gpu-node
  ├── lan-only-network
  ├── audit-and-aide
  ├── agent-sandbox
  └── ai-services
        └── (depends on gpu-node, agent-sandbox, lan-only-network)
```

## Threat Model

**Protected assets:** Model artifacts, inference prompts/responses, agent actions, audit logs, sensitive data (ePHI, CHD, PII)

**Adversary model:**
- External attacker with LAN access (compromised device)
- Malicious/compromised input data (prompt injection, poisoned docs)
- Compromised model weights (supply chain attack)
- Insider with unprivileged local account

**Excluded:** Nation-state with physical access, hardware implants, side-channel attacks, compromised NixOS upstream

## Data Flows

### Inference Request
Client (LAN) → TLS/mTLS → Firewall → Rate Limiter → Input Logger → Inference Engine → Output Logger → Client

### Agentic Workflow
Agent Request → Approval Gate → Tool Allowlist → Sandboxed Execution → Action Logger → Result → Agent

### Audit & Evidence
System Events → auditd + journald → Local Log Store → AIDE → Drift Alerting → Evidence Generator → IR Hooks

### RAG Pipeline
Document Ingestion → Access Control → Embedding Model → Vector Store (encrypted) → Query → Context Assembly → Inference → Output (with citations)

## Security Principles

1. **Least exposure** — LAN-only, no public Internet
2. **Least privilege** — minimal permissions for users, services, agents
3. **Reproducible baseline** — full state in version-controlled Nix config
4. **Control traceability** — every safeguard maps to formal control objectives
5. **Defense in depth** — controls at kernel, OS, network, service, app levels
6. **Model supply chain integrity** — verified checksums, provenance tracking

## Delivery Phases

- **Phase 1:** Foundation (stig-baseline, lan-only-network, audit-and-aide, control matrix)
- **Phase 2a:** GPU and Drivers (gpu-node)
- **Phase 2b:** AI Services and Agents (ai-services, agent-sandbox)
- **Phase 3:** Compliance Validation (evidence generation)
- **Phase 4:** Hardening and Final Validation
