# PRD: Control-Mapped NixOS AI Agentic Server

## 1. Overview

This document defines the master product requirements for a LAN-only, hardened NixOS-based AI server designed for local GPU inference and agentic workflows on a repurposed GPU workstation. The system is compliance-mapped from inception: every technically-enforceable control from all target regulatory and security frameworks is implemented declaratively through NixOS flake modules.

The goal is not aspirational alignment but concrete implementation. Each security control is traced to one or more formal framework requirements, implemented as reproducible NixOS configuration, and verified through automated evidence generation. The system treats compliance as an engineering deliverable, not a governance exercise.

Detailed requirements for each compliance framework are maintained in dedicated module files. This umbrella PRD defines the shared architecture, cross-cutting concerns, and the mapping between frameworks and flake modules.

### 1.1 Threat Model

**Protected assets**: Model artifacts, inference prompts/responses, agent actions, audit logs, and any sensitive data (ePHI, CHD, PII) processed through the AI pipeline.

**Adversary model**: 
- External attacker with LAN access (compromised device on the same network)
- Malicious or compromised input data (prompt injection, poisoned documents)
- Compromised model weights (supply chain attack)
- Insider with unprivileged local account

**Excluded threats**: Nation-state with physical access, hardware implants, side-channel attacks on CPU/GPU, compromised NixOS upstream infrastructure.

**Primary risk**: Unauthorized access to sensitive data via the AI inference pipeline — through direct network access, prompt injection, agent tool misuse, or log contamination.

## 2. Compliance Targets

| Framework | Scope | Module File |
|---|---|---|
| NIST SP 800-53 Rev 5 | All 20 control families (AC, AU, AT, CM, CP, IA, IR, MA, MP, PE, PL, PM, PS, RA, SA, SC, SI, SR, CA, PT) | [prd-nist-800-53.md](prd-nist-800-53.md) |
| HIPAA | Security Rule, Privacy Rule, Breach Notification Rule technical safeguards | [prd-hipaa.md](prd-hipaa.md) |
| HITRUST CSF v11 | All 14 control domains | [prd-hitrust.md](prd-hitrust.md) |
| PCI DSS v4.0 | All 12 requirements for cardholder data environment security | [prd-pci-dss.md](prd-pci-dss.md) |
| OWASP Top 10 for LLMs | LLM-specific vulnerabilities plus OWASP Agentic AI threat categories | [prd-owasp.md](prd-owasp.md) |
| NIST AI RMF | AI risk management lifecycle (Govern, Map, Measure, Manage) | [prd-ai-governance.md](prd-ai-governance.md) |
| EU AI Act | High-risk AI system technical requirements | [prd-ai-governance.md](prd-ai-governance.md) |
| ISO 42001 | AI management system controls | [prd-ai-governance.md](prd-ai-governance.md) |
| MITRE ATLAS | Adversarial threat landscape for AI systems | [prd-ai-governance.md](prd-ai-governance.md) |
| STIG / DISA | Anduril NixOS STIG findings and DISA hardening expectations | [prd-stig-disa.md](prd-stig-disa.md) |

## 3. Architecture

The system is built as a NixOS flake with six primary modules. Each module owns a defined set of controls and can be enabled, configured, and tested independently.

### 3.1 Flake Module Structure

**`stig-baseline`** — OS hardening, kernel, SSH, PAM, audit, accounts.
Implements the foundational host security posture: kernel hardening parameters, SSH lockdown (key-only, no root, MFA for privileged access), PAM configuration, account policies, login banners, service minimization, and boot integrity. This module is the foundation that all other modules build on.

**`gpu-node`** — NVIDIA drivers, CUDA, AI runtimes.
Manages proprietary NVIDIA driver installation, CUDA toolkit provisioning, and AI runtime dependencies. Balances driver requirements against the hardened profile, documenting any necessary exceptions to the security baseline.

**`lan-only-network`** — Firewall, interface binding, egress filtering, NTP.
Enforces LAN-only network posture: inbound traffic restricted to approved interfaces and subnets, explicit port allowlisting, egress filtering to prevent unauthorized outbound connections, DNS restrictions, and NTP synchronization for log correlation and certificate validation.

**`audit-and-aide`** — auditd, AIDE, log retention, drift alerting, evidence generation.
Configures comprehensive audit logging (auditd rules, journald persistence, log rotation), file integrity monitoring via AIDE with scheduled checks, drift detection with alerting, log retention policies, and automated evidence generation for compliance audits.

**`agent-sandbox`** — systemd isolation, tool allowlisting, approval gates, resource quotas.
Provides runtime isolation for AI agents using systemd security directives (PrivateTmp, ProtectSystem, NoNewPrivileges, namespace isolation, seccomp filters). Implements tool allowlisting, human-in-the-loop approval gates for high-risk actions, resource quotas (CPU, memory, file descriptors), and network access restrictions per agent.

**`ai-services`** — Ollama, inference APIs, model registry, rate limiting, TLS termination.
Manages the AI inference stack: Ollama service configuration, inference API endpoints, model registry with provenance tracking, per-client rate limiting, TLS termination for internal traffic, input/output logging, and prompt injection mitigations.

### 3.2 Module Dependency Order

```
stig-baseline
  ├── gpu-node
  ├── lan-only-network
  ├── audit-and-aide
  ├── agent-sandbox
  └── ai-services
        └── (depends on gpu-node, agent-sandbox, lan-only-network)
```

## 4. Security Principles

1. **Least exposure**: The server accepts traffic only from trusted local interfaces and subnets. No public Internet ingress. No unnecessary listening services.

2. **Least privilege**: Users, services, and agents receive only the permissions required for their function. Agents cannot escalate without explicit approval.

3. **Reproducible baseline**: The full system state is declared in version-controlled Nix configuration. Any deployment is reproducible from the flake, and any drift from the declared state is detectable.

4. **Control traceability**: Every safeguard maps to one or more formal control objectives across the target frameworks. The mapping is maintained in a structured control matrix.

5. **Defense in depth**: Controls are layered at the kernel, OS, network, service, and application levels. No single control failure compromises the security posture.

6. **Model supply chain integrity**: Models are verified against known checksums or signatures before deployment. Provenance is tracked from acquisition through serving. Unauthorized model substitution is detected.

## 5. Cross-Framework Control Matrix

This table shows which flake modules implement controls for which frameworks. Detailed control-level mappings are in each framework module file.

| Flake Module | NIST 800-53 | HIPAA | HITRUST | PCI DSS | OWASP LLM/Agentic | AI Gov (RMF/EU/ISO/ATLAS) | STIG/DISA |
|---|---|---|---|---|---|---|---|
| `stig-baseline` | AC, IA, CM, SC, SI | Access Control, Audit, Auth | Access Control, Config Mgmt | Req 2, 5, 6, 8 | Reduced attack surface | System security foundation | Primary |
| `gpu-node` | CM, SA, SI | Integrity | Asset Mgmt, Config Mgmt | Req 6 | Model runtime integrity | Model deployment controls | Driver exceptions |
| `lan-only-network` | AC, SC, CA | Transmission Security | Network Protection | Req 1, 4 | Tool misuse mitigation | Network isolation | Boundary protection |
| `audit-and-aide` | AU, CM, SI, IR | Audit Controls, Integrity | Audit Logging, Monitoring | Req 10, 11, 12 | Abuse detection | Monitoring, evidence | Audit/drift findings |
| `agent-sandbox` | AC, SC, SI, AU | Min Necessary, Access Control | Access Control, Risk Mgmt | Req 7, 8 | Tool restriction, sandboxing | Agent risk controls | Process isolation |
| `ai-services` | AC, SC, SI, AU | ePHI handling, Encryption | Data Protection, Crypto | Req 3, 4, 8 | Prompt injection, data leakage | Model governance, bias | Service hardening |

## 6. Data Flows

Data moves through the system in a controlled pipeline with security controls enforced at each stage.

### 6.1 Inference Request Flow

```
Client (LAN) ──[TLS/mTLS]──> Firewall (port allowlist)
  ──> Rate Limiter (per-client throttling)
  ──> Input Logger (prompt metadata, no secrets)
  ──> Inference Engine (Ollama / API)
  ──> Output Logger (response metadata)
  ──> Client
```

**Controls at each stage:**
- **Network entry**: Firewall validates source interface/subnet, TLS terminates at service boundary
- **Rate limiting**: Prevents resource exhaustion and abuse
- **Input logging**: Captures request metadata for audit trail without storing sensitive content in logs
- **Inference**: Runs under service account with minimal privileges, GPU access scoped to inference process
- **Output logging**: Captures response metadata, flags potential data leakage patterns
- **Response delivery**: Encrypted in transit back to client

### 6.2 Agentic Workflow Flow

```
Agent Request ──> Approval Gate (high-risk check)
  ──> Tool Allowlist (permitted tools only)
  ──> Sandboxed Execution (systemd isolation)
  ──> Action Logger (tool, args, result)
  ──> Result ──> Agent
```

**Controls at each stage:**
- **Approval gate**: Human-in-the-loop for shell execution, file deletion, credential access, external writes
- **Tool allowlist**: Only explicitly permitted tools are callable
- **Sandbox**: PrivateTmp, ProtectSystem, namespace isolation, seccomp, resource quotas
- **Action logging**: Every tool invocation is logged with arguments and results for audit
- **Result delivery**: Output sanitized before return to agent context

### 6.3 RAG Ingestion and Retrieval Flow

Retrieval-augmented generation is a structurally distinct data path from §6.1. It introduces an **ingestion-time** pipeline (source → chunks → vectors → index) that runs before any inference occurs, and a **retrieval-time** pipeline that composes retrieved chunks into the inference request. Each stage introduces controls that the inference flow alone does not express.

```
Source ──[provenance record]──> Chunker ──[chunk metadata]──> Embedder
  ──[versioned vector]──> Vector Store (encrypted at rest)
  ──[Query]──> Retrieval (top-k + lineage) ──> Inference (§6.1)
```

**Controls per stage:**
- **Source acquisition (file, URL, upload)**: provenance record captures source URI, acquisition timestamp, content hash, and consent/licensing metadata; input size limits enforced; file-type allowlist rejects executable and opaque binary formats.
- **Chunking**: chunker version stamped into every chunk record; per-chunk metadata preserves parent document hash, chunk index, and chunker configuration version so a retrieved chunk can be traced to its exact split.
- **Embedding**: embedding model version stamped alongside each vector; deterministic-or-nondeterministic flag recorded so reproducibility claims are honest; model source verification ties into the model supply chain controls (see §7.8).
- **Index storage (vector store)**: encryption at rest (LUKS for the storage volume; see §7.1); access control is UID-scoped to the retrieval service account; per-chunk lineage fields from earlier stages are preserved so retrieval can reconstruct full provenance.
- **Retrieval (query → top-k)**: retrieval audit log records the query, chunks returned, and relevance scores; per-query rate limiting applies independently of §6.1 inference rate limits; classification-tier gating prevents Restricted-tier chunks from being retrieved into a non-Restricted inference context (see §7.16).
- **Inference composition**: retrieved chunks and the user query are injected into the LLM prompt; chunk provenance is propagated into inference logs so every response is traceable to its sources; indirect-prompt-injection mitigations (instruction stripping, delimiter fencing) apply to retrieved content; tier-mixing across Restricted / Confidential / Internal boundaries is prohibited within a single composed prompt.

**Retention**: retrieval audit logs follow the canonical AI decision log retention of 18 months (see `modules/canonical/default.nix` `logRetention.aiDecisionLogs = "18month"`).

**Framework driver**: ISO 42001 Annex A.6.2 (data management) — see `docs/prd/prd-ai-governance.md` §A.6 and §3.2.1 for the RAG-specific data governance requirements this flow operationalises.

**Residual risk**: this flow enumerates the controls a future RAG application must implement; it does not eliminate the application-layer lineage gap. See `docs/residual-risks.md` row 6 ("RAG Data Lineage and Versioning") for what infrastructure cannot mitigate on its own.

**Implementation status**: **not currently implemented.** This repository contains no RAG application code, no vector store module, and no retrieval service. §6.3 is documented as an **aspirational flow** so downstream modules and residual-risk tracking have a single architectural reference. The future AI-20 TODO will materialise this flow — selecting a vector store, defining the chunk schema, and wiring the ingestion and retrieval services into the flake — at which point the stage-by-stage controls above become implementation requirements rather than design intent.

### 6.4 Audit and Evidence Flow

```
System Events ──> auditd + journald ──> Local Log Store
  ──> AIDE (integrity baseline comparison)
  ──> Drift Alerting (notify on unauthorized changes)
  ──> Evidence Generator (periodic compliance snapshots)
  ──> Incident Response Hooks (threshold-based triggers)
```

## 7. Shared Requirements

These requirements are demanded by multiple frameworks and are implemented once in the appropriate flake module.

### 7.1 Full-Disk Encryption (LUKS)

All data at rest — model artifacts, prompts, logs, configuration, and stored outputs — is protected by LUKS full-disk encryption. Encryption keys are managed outside the Nix store. This satisfies at-rest protection requirements across NIST SC-28, HIPAA encryption safeguards, PCI DSS Requirement 3, HITRUST encryption domains, and STIG storage protections.

### 7.2 SSH Hardening

SSH requires key-based authentication, disables password and keyboard-interactive login, prohibits direct root login, restricts allowed users, and enforces MFA for privileged remote access. X11 forwarding is disabled. Idle sessions are terminated. This satisfies identification and authentication controls across all target frameworks.

### 7.3 Audit Logging

auditd captures security-relevant kernel events. journald captures service-level logs with persistent storage. Log retention meets the longest required period across all frameworks (minimum one year for PCI DSS, or as required by organizational policy). Logs do not contain secrets, credentials, or unmasked sensitive data. Log integrity is protected against tampering.

### 7.4 NTP Synchronization

System time is synchronized via NTP to authoritative sources for accurate log timestamps, certificate validation, and audit record correlation. Time sources are restricted to approved servers. This is required by NIST AU-8, PCI DSS Requirement 10, HIPAA audit controls, and STIG time synchronization findings.

### 7.5 File Integrity Monitoring (AIDE)

AIDE performs scheduled integrity checks against a known-good baseline. Unauthorized changes to system files, configuration, and binaries trigger alerts to designated personnel. The baseline is regenerated after authorized changes. This satisfies integrity monitoring requirements across NIST SI-7, PCI DSS Requirement 11, HIPAA integrity controls, and STIG drift detection findings.

### 7.6 Egress Filtering

Outbound network traffic is restricted to explicitly approved destinations and protocols. Unauthorized egress is blocked and logged. This prevents data exfiltration, unauthorized model downloads, and agent-initiated external connections. Satisfies boundary protection controls across NIST SC-7, PCI DSS Requirement 1, and OWASP tool misuse mitigations.

### 7.7 Agent Sandboxing

All AI agents run in systemd-isolated execution environments with: no new privileges, private /tmp, read-only system paths, restricted address families, resource quotas, and explicit read-write path declarations. Agents cannot break out of their sandbox without exploiting a kernel vulnerability. This is the primary mitigation for OWASP Agentic AI threats and supports least-privilege requirements across all frameworks.

### 7.8 Model Provenance Verification

Models are verified against known checksums or cryptographic signatures before deployment to the inference stack. The model registry tracks acquisition source, version, hash, and deployment history. Unauthorized model substitution or tampering is detected by AIDE and logged. This satisfies MITRE ATLAS model supply chain controls, NIST AI RMF model governance, and EU AI Act transparency requirements.

### 7.9 Evidence Generation Automation

Automated scripts generate compliance evidence packages: configuration snapshots, audit log extracts, AIDE reports, firewall rule dumps, user/group listings, service inventories, and encryption status. Evidence is timestamped and stored for audit retrieval. This supports audit readiness across all frameworks and reduces manual evidence collection burden.

### 7.10 Incident Response Hooks

Threshold-based triggers initiate incident response actions: AIDE drift alerts, failed authentication spikes, unauthorized egress attempts, agent sandbox violations, and service anomalies. Hooks notify designated personnel and can trigger automated containment actions (service restart, network isolation). This satisfies incident response requirements across NIST IR, HIPAA breach notification, PCI DSS Requirement 12, and HITRUST incident management.

### 7.11 Backup and Recovery

System configuration is fully recoverable from the Git-managed flake repository. Data backups cover model artifacts, logs, and application state with encrypted storage. Recovery procedures are documented and testable: a fresh NixOS deployment can be rebuilt to the hardened baseline from the flake without undocumented manual steps. NixOS generation rollback provides immediate recovery from failed updates. This satisfies contingency planning requirements across NIST CP, HIPAA contingency plan, PCI DSS Requirement 12, and HITRUST business continuity.

### 7.12 Vulnerability Management

The system tracks NixOS security advisories and upstream CVEs for all deployed packages, drivers, and model-serving components. Patch cycles are defined and enforced. NVIDIA driver and CUDA updates are tested against the hardened baseline before deployment. This satisfies vulnerability management requirements across NIST RA/SI, PCI DSS Requirement 6, HIPAA risk management, and STIG patching findings.

### 7.13 Secrets Management

Secrets (TLS certificates, SSH host keys, LUKS passphrases, API tokens, TOTP seeds, backup encryption keys) are managed via **sops-nix** with age encryption. The choice is committed — agenix is not supported. See `modules/secrets/default.nix` for the authoritative per-secret declaration list. Secrets are:
- Encrypted at rest in the Git repository using age keys
- Decrypted at activation time to `/run/secrets/` (tmpfs, not persisted to disk)
- Not present in the Nix store or in plaintext in any committed file
- Rotated on a defined schedule (TLS: annual, SSH host keys: on compromise, API tokens: quarterly)

### 7.14 Boot Integrity

UEFI Secure Boot is enabled to ensure only signed bootloaders and kernels execute. Verified via `mokutil --sb-state`. LUKS full-disk encryption depends on boot integrity — without Secure Boot, an attacker with physical access can modify the bootloader to capture the LUKS passphrase.

### 7.15 Account Lifecycle Management

User accounts are managed declaratively via `users.users` in the flake configuration. Account lifecycle controls include:
- **Access review cadence**: Quarterly review of all user accounts and group memberships
- **De-provisioning procedure**: Remove the user from `users.users` in the flake and rebuild; NixOS ensures the account no longer exists on the target system
- **Credential rotation schedule**: SSH keys rotated annually, TOTP seeds on compromise, service account tokens quarterly
- **Audit trail**: All account changes are tracked through Git history and auditd account modification events

### 7.16 Data Classification

All data processed, stored, or transmitted by the system is classified according to the following scheme:

| Level | Label | Examples | Handling Requirements |
|---|---|---|---|
| 1 | **Public** | Published model metadata, system version | No special controls beyond integrity |
| 2 | **Internal** | Inference logs (non-sensitive), system configuration, AIDE baselines | Encrypted at rest, access restricted to authorized operators |
| 3 | **Sensitive** | ePHI, CHD, PII, inference prompts/responses containing regulated data | Encrypted at rest and in transit, audit-logged access, retention per framework, masked in logs |
| 4 | **Restricted** | LUKS passphrases, age private keys, TLS private keys, TOTP seeds, API tokens | Managed exclusively via sops-nix, never in plaintext, never in Nix store, access limited to activation-time decryption |

Data classification determines which framework controls apply. Classification is assigned at ingestion for RAG documents and at configuration time for system-managed data.

## 8. Scope Boundaries

This project implements every technical control that can be enforced through host-level NixOS configuration. The system is designed as a **single-tenant, single-operator deployment** on a dedicated GPU workstation — not a multi-user shared platform or a clustered service. All controls assume a single administrative domain with one or a small number of trusted operators.

The following boundaries define what is in scope and what requires complementary measures outside this system:

**In scope (implemented by the flake):**
- All OS-level, network-level, and service-level technical controls
- Agent runtime isolation and tool restrictions
- Audit logging, integrity monitoring, and evidence generation
- Encryption at rest and in transit for host-managed services
- Model provenance verification and registry management
- Automated incident response triggers

**Requires complementary measures (not solely solvable by host config):**
- Administrative policies, workforce training, and governance documentation
- Physical security of the workstation and its environment
- Business associate agreements and data processing contracts
- Risk assessments, privacy impact assessments, and formal authorization processes
- Third-party audit engagements and certification submissions
- Application-layer prompt injection defenses beyond infrastructure controls
- Human review processes for AI outputs in high-risk decision contexts

The design philosophy is: implement every technical control possible at the host and service layer, document what remains, and provide hooks for organizational processes to complete the picture.

## 9. Users and Use Cases

**Primary users**: Technical operators, security engineers, or platform engineers running local models and agentic workflows on a private GPU host while maintaining alignment to formal compliance controls.

**Use cases:**
- Local inference APIs for internal applications
- Coding agents with controlled tool access
- Internal RAG pipelines over private data
- Agentic workflows with human-in-the-loop approval for sensitive actions
- Compliance evidence generation for auditors
- Security baseline validation and drift monitoring

## 10. Acceptance Criteria

1. A fresh NixOS deployment rebuilds from the flake to the hardened baseline without undocumented manual steps.
2. The host exposes only approved LAN-side service ports and rejects all other inbound traffic.
3. MFA requires key + TOTP (or FIDO2) for all remote admin sessions.
4. Full-disk encryption (LUKS) is enabled and verifiable.
5. auditd, journald, and AIDE are operational and producing verifiable evidence.
6. AIDE detects unauthorized file changes and triggers alerts.
7. Egress filtering blocks unauthorized outbound connections.
8. NTP synchronization is active and verified.
9. Agent sandbox: ProtectSystem=strict, NoNewPrivileges=true, MemoryMax≤4GB, explicit ReadWritePaths only.
10. Model provenance is verified before deployment; unauthorized substitution is detected.
11. Rate limiting: ≤30 requests/min/client on inference endpoints.
12. TLS is active for all service traffic, even on the LAN.
13. Secrets are not present in the Nix store or Git repository.
14. Evidence generation produces timestamped packages including: firewall rules, audit config, user list, AIDE report, SSH config, NTP status, encryption status.
15. NixOS generation rollback restores the previous known-good state.
16. The configuration maps to specific control requirements across all target frameworks via the control matrix.
17. Incident response hooks fire on defined threshold events.
18. The system is maintainable by a small engineering team or a single advanced operator.

## 11. Risks and Open Questions

### Risks

1. **NVIDIA driver compatibility**: Proprietary drivers and CUDA versions may conflict with kernel hardening parameters. Each driver update must be validated against the security baseline.

2. **Performance vs. security tradeoffs**: Some hardening measures (seccomp filters, namespace isolation, CPU quotas) may impact inference throughput. Performance testing must quantify the impact.

3. **Framework overlap and conflict**: Multiple frameworks may impose contradictory requirements (e.g., log retention periods, encryption algorithm requirements). Conflicts are resolved in Appendix A toward the strictest applicable requirement.

4. **Application-layer gaps**: Host-level controls cannot fully prevent prompt injection, indirect prompt injection, or semantic attacks on LLM outputs. Application-layer defenses are complementary and outside the flake scope. See [`docs/residual-risks.md`](../residual-risks.md) for the full list of risks that infrastructure does not and cannot eliminate.

5. **Single-host architecture**: This design targets a single workstation. Scaling to multiple nodes would require additional controls for inter-node communication, distributed logging, and coordinated drift detection.

6. **Agent sandbox escapes**: systemd isolation is strong but not equivalent to a hypervisor boundary. Kernel vulnerabilities could allow sandbox escape. Defense in depth and monitoring are mitigations, not guarantees.

7. **Audit volume**: Comprehensive auditd rules across all frameworks may generate high log volumes, requiring tuning to balance completeness against storage and performance.

8. **NixOS upstream breakage**: NixOS is a rolling distribution, and a locked flake pins all packages at a point in time. If the flake lock is not updated regularly, deployed packages may accumulate unpatched CVEs. Conversely, updating the lock may introduce regressions. A defined flake-update cadence with automated CVE scanning (vulnix) mitigates this risk.

9. **Compliance framework version drift**: HITRUST CSF, PCI DSS, and the EU AI Act are all actively evolving. Control mappings in this PRD and the framework modules must be reviewed when new versions are published. A version-pinned compliance target (e.g., "PCI DSS v4.0" not "PCI DSS latest") prevents scope creep but requires periodic re-baselining.

10. **GPU VRAM as unencrypted sensitive data exposure**: GPU VRAM is not encrypted at rest or in transit between GPU and host memory. Inference prompts and responses containing ePHI, CHD, or PII exist in plaintext in VRAM during processing. An attacker with physical access or a kernel exploit could dump VRAM contents. Mitigation is limited to physical security, kernel hardening, and minimizing retention of sensitive data in GPU memory.

### Open Questions

1. Which STIG tailoring profile applies — enterprise-managed, standalone, or enclave component?
2. What is the required log retention period when frameworks specify different minimums?
3. Should model provenance use GPG signatures, SLSA attestations, or both?
4. What is the MFA mechanism for SSH — TOTP, FIDO2, or certificate-based?
5. Should agent approval gates be synchronous (blocking) or asynchronous (queued)?
6. What is the recovery time objective (RTO) for full system rebuild from flake?
7. How are NVIDIA driver security advisories tracked and integrated into the patch cycle?
8. What data classification applies to this system's workloads? The applicable framework subset depends on whether the system processes ePHI, CHD, CUI, or only internal non-sensitive data.

## 12. Delivery Plan

### Phase 1: Foundation
- Flake repository structure with all six modules stubbed
- `stig-baseline` module: kernel hardening, SSH, PAM, accounts, banners, service minimization
- `lan-only-network` module: firewall, interface binding, egress filtering, NTP
- `audit-and-aide` module: auditd rules, journald persistence, AIDE baseline, drift alerting
- Control matrix spreadsheet mapping specific Nix options to control requirements across all frameworks

### Phase 2a: GPU and Drivers
- `gpu-node` module: NVIDIA drivers, CUDA, runtime dependencies, driver exception documentation
- Validation: GPU passthrough functional under hardened kernel, driver exceptions documented

### Phase 2b: AI Services and Agents
- `ai-services` module: Ollama, inference APIs, model registry, rate limiting, TLS
- `agent-sandbox` module: systemd isolation, tool allowlisting, approval gates, resource quotas
- Depends on Phase 2a (`ai-services` requires validated `gpu-node`)

### Phase 3: Compliance Validation
- Validation checklist: rebuild testing, port verification, SSH verification, drift detection, sandbox breakout tests, evidence generation verification
- Evidence generation automation: scripts producing timestamped compliance packages

### Phase 4: Hardening and Validation
- Cross-framework gap analysis and remediation
- Performance testing with full hardening profile active
- Incident response hook implementation and testing
- Backup and recovery procedure validation
- Final control matrix review against all framework module files

### Deliverables
1. NixOS flake with six modules implementing all technically-enforceable controls
2. Control matrix spreadsheet (framework requirement to Nix option mapping)
3. Validation checklist with pass/fail criteria for each control
4. Evidence generation automation scripts
5. Framework module PRDs (one per compliance target)
6. Deployment guide including LUKS setup, first-boot procedures, and rollback instructions

## 13. Document Index

| Document | Description |
|---|---|
| [prd-nist-800-53.md](prd-nist-800-53.md) | NIST SP 800-53 Rev 5 — all 20 control families with per-family requirements and Nix implementation guidance |
| [prd-hipaa.md](prd-hipaa.md) | HIPAA Security Rule, Privacy Rule, and Breach Notification Rule technical safeguard requirements |
| [prd-hitrust.md](prd-hitrust.md) | HITRUST CSF v11 — all 14 control domains with implementation requirements |
| [prd-pci-dss.md](prd-pci-dss.md) | PCI DSS v4.0 — all 12 requirements for cardholder data environment security |
| [prd-owasp.md](prd-owasp.md) | OWASP Top 10 for LLMs and OWASP Agentic AI threat mitigations |
| [prd-ai-governance.md](prd-ai-governance.md) | NIST AI RMF, EU AI Act, ISO 42001, MITRE ATLAS, and model supply chain requirements |
| [prd-stig-disa.md](prd-stig-disa.md) | Anduril NixOS STIG findings and DISA hardening expectations |

## Appendix A: Canonical Configuration Values

These values resolve conflicts between framework-specific requirements. The implementation flake uses ONLY these values. Framework module files define *requirements*; this appendix defines the *resolved implementation*.

**All inline Nix snippets in framework module files are illustrative only.** When a module file's snippet uses a value that differs from this appendix, the appendix value takes precedence. Implementers must use this appendix as the single source of truth for every setting listed below.

### A.1 Service Binding

| Setting | Resolved Value | Driving Framework | Conflict Resolved |
|---|---|---|---|
| Ollama listen address | `OLLAMA_HOST = "127.0.0.1:11434"` | STIG, HIPAA (defense-in-depth) | NIST module used `0.0.0.0:11434` — **rejected**. Ollama has no authentication; binding to all interfaces exposes an unauthenticated inference API. All LAN access must go through the Nginx TLS reverse proxy. |
| Ollama ORIGINS | `OLLAMA_ORIGINS = "http://127.0.0.1:*"` | HIPAA §164.312(d) | Prevents cross-origin requests from LAN clients bypassing the API gateway. |
| SSH listen address | LAN interface only (e.g., `192.168.1.50`) via `services.openssh.listenAddresses` | All frameworks | Not `0.0.0.0`. Bind to the specific LAN interface address. |
| Application API (port 8000) | Bind to `127.0.0.1:8000`; expose via Nginx TLS proxy | STIG, PCI DSS Req 4 | Same pattern as Ollama: no direct LAN exposure of unencrypted services. |

### A.2 Firewall Technology

| Setting | Resolved Value | Driving Framework | Conflict Resolved |
|---|---|---|---|
| Firewall backend | **nftables** exclusively | NixOS 24.11 default, PCI DSS, HITRUST | NIST, HIPAA, and STIG modules used `networking.firewall.extraCommands` with iptables syntax. NixOS 24.11 defaults to nftables as the firewall backend. Using legacy iptables `extraCommands` may silently fail or produce undefined behavior. **All firewall rules must use `networking.nftables.ruleset` or `networking.firewall` (which generates nftables rules internally).** Do not use `networking.firewall.extraCommands` with raw iptables syntax. |
| Default policy | Default deny inbound; explicit allowlist per interface | All frameworks | Use `networking.firewall.enable = true` with interface-level `allowedTCPPorts`. |
| Egress filtering | Per-UID output filtering via nftables, not iptables `--uid-owner` | HIPAA, OWASP | nftables equivalent: `meta skuid ollama` in output chain rules. |

### A.3 systemd Hardening Directives

| Setting | Resolved Value | Applies To | Conflict Resolved |
|---|---|---|---|
| `MemoryDenyWriteExecute` | **`true`** | `agent-runner`, `ai-api`, all non-GPU services | OWASP module set this on the Ollama service — **rejected**. |
| `MemoryDenyWriteExecute` | **omit (do not set)** | `ollama`, any CUDA/GPU inference service | CUDA requires W+X memory for JIT compilation of PTX kernels. Setting `MemoryDenyWriteExecute=true` on a CUDA-facing service **crashes GPU inference at runtime**. Compensating controls: `SystemCallFilter`, `RestrictAddressFamilies`, `ProtectSystem=strict`, `NoNewPrivileges=true`. See HIPAA §2.3.3 for full rationale. |
| `ProtectSystem` | **`"strict"`** | All services including Ollama | NIST module used `"full"` for Ollama — **rejected**. `"strict"` makes the entire filesystem read-only; GPU access is handled via explicit `ReadWritePaths` and `DeviceAllow` entries. `"full"` only protects `/usr` and `/boot`, which is insufficient. |
| `NoNewPrivileges` | `true` | All service units | Consensus across all frameworks. Defined once per service in the implementation flake; do not duplicate in PRD modules. |
| `PrivateTmp` | `true` | All service units | Consensus. |
| `ProtectHome` | `true` | All service units | Consensus. |

### A.4 SSH Cryptographic Configuration

These values apply to `services.openssh.settings` in the `stig-baseline` module.

| Setting | Resolved Value | Driving Framework | Conflict Resolved |
|---|---|---|---|
| `PasswordAuthentication` | `false` | All frameworks | Consensus. Key-only authentication. |
| `KbdInteractiveAuthentication` | **`true`** | NIST IA-2(1), PCI DSS, STIG MFA | STIG SSH hardening and HITRUST set this to `false` — **overridden by MFA requirement**. TOTP MFA via google-authenticator PAM requires keyboard-interactive to be enabled. Without it, MFA is broken. The `AuthenticationMethods` directive ensures keyboard-interactive is used only for TOTP, never for password auth. |
| `AuthenticationMethods` | `"publickey,keyboard-interactive"` | All frameworks requiring MFA | Ensures both key and TOTP are required. |
| `PermitRootLogin` | `"no"` | All frameworks | Consensus. |
| `X11Forwarding` | `false` | All frameworks | Consensus. |
| `AllowUsers` | `[ "admin" ]` (adjust per deployment) | STIG, NIST AC-17 | Explicit allowlist of interactive users. |
| `MaxSessions` | `3` | NIST AC-10 | |
| `MaxStartups` | `"10:30:60"` | NIST SC-5 | Rate-limit SSH connection attempts. |
| `Ciphers` | `aes256-gcm@openssh.com`, `aes128-gcm@openssh.com`, `aes256-ctr`, `aes128-ctr` | STIG FIPS | NIST and PCI modules included `chacha20-poly1305@openssh.com` — **removed for FIPS compatibility**. ChaCha20-Poly1305 is not FIPS-approved. If FIPS is not required for deployment, ChaCha20 may be re-added as the first cipher for performance. |
| `Macs` | `hmac-sha2-512-etm@openssh.com`, `hmac-sha2-256-etm@openssh.com` | STIG FIPS | STIG FIPS section included non-ETM variants — **removed**. ETM (encrypt-then-MAC) is strictly stronger. |
| `KexAlgorithms` | `curve25519-sha256`, `curve25519-sha256@libssh.org`, `ecdh-sha2-nistp521`, `ecdh-sha2-nistp384`, `ecdh-sha2-nistp256` | STIG + NIST combined | NIST used only curve25519; STIG FIPS used only NIST P-curves. Combined list supports both FIPS and non-FIPS clients. For strict FIPS-only: remove curve25519 entries. |
| `ClientAliveInterval` | `600` | STIG (master PRD resolved) | HIPAA used 300, NIST/PCI/HITRUST used 300. STIG resolved to 600. |
| `ClientAliveCountMax` | `0` | STIG | Disconnect immediately after one missed keepalive (600s total). NIST/PCI used `3`, which yields 900s — **STIG's stricter value prevails**. |
| **Deprecated options — DO NOT USE** | | | |
| `Protocol 2` | **Do not set** | OpenSSH 7.6+ | Removed from OpenSSH. Setting it causes sshd to fail to start on NixOS (ships OpenSSH 9.x). |
| `ChallengeResponseAuthentication` | **Do not set** | OpenSSH 8.7+ | Deprecated alias for `KbdInteractiveAuthentication`. Setting both creates conflicts. Use only `KbdInteractiveAuthentication`. |

### A.5 Log Retention

| Setting | Resolved Value | Driving Framework | Notes |
|---|---|---|---|
| `MaxRetentionSec` (systemd journal) | `365day` | PCI DSS 10.5.1, HITRUST Level 2 | Operational audit logs. NIST/STIG specified 90 days (insufficient). HIPAA used 26280h (~3 years, conflating documentation retention with log retention). The 1-year value satisfies PCI's "1 year with 3 months immediately queryable" requirement. |
| `SystemMaxUse` (journal disk) | `10G` | Operational | Adjust based on available storage. |
| `ForwardToSyslog` | `yes` | HIPAA §164.312(b) | For remote log forwarding via TLS-encrypted transport (RELP or Vector). |
| AI decision logs retention | 18 months | EU AI Act Art. 12 | Separate structured per-request log stream, not systemd journal. |
| Policy documentation retention | 6 years | HIPAA §164.316(b) | Git repository with 6-year archive. Not journal retention. |

### A.6 Authentication and Account Policy

| Setting | Resolved Value | Driving Framework | Conflict Resolved |
|---|---|---|---|
| Password minimum length | 15 characters | STIG, HITRUST Level 2 | PCI DSS v4.0 requires 12 — STIG/HITRUST is stricter. |
| Password history (`pam_pwhistory remember=`) | 24 | HITRUST Level 2 | STIG specified `remember=5` — **HITRUST's stricter value prevails**. |
| Password max age (`PASS_MAX_DAYS`) | 60 days | STIG | HITRUST allows 365 days. STIG is stricter. Note: NIST 800-63B recommends against periodic rotation, but STIG prescribes it. |
| Account lockout threshold (`pam_faillock deny=`) | 5 attempts | STIG, HITRUST | PCI DSS used 6 — **STIG/HITRUST's stricter value prevails**. |
| Account lockout duration (`unlock_time`) | 1800 seconds (30 min) | HITRUST Level 2, PCI DSS | STIG used 900s (15 min) — **HITRUST/PCI's stricter value prevails**. Master PRD Appendix A previously said "15 min" — **corrected to 30 min**. |
| Account lockout find interval | 900 seconds | STIG, HITRUST, PCI DSS | Consensus. |
| Session idle timeout (SSH) | 600 seconds (10 min) | STIG | See A.4 `ClientAliveInterval` / `ClientAliveCountMax`. |
| Session idle timeout (shell `TMOUT`) | 600 seconds | STIG | HITRUST/PCI used 900. STIG is stricter. |
| MFA scope | All remote admin access | PCI DSS v4.0, STIG, NIST IA-2(1) | Implemented via TOTP (google-authenticator PAM). |
| MFA mechanism | TOTP via google-authenticator PAM (primary), FIDO2/ed25519-sk (alternative) | Operational | |
| `sudo` timestamp timeout | 5 minutes | NIST IA-11 | Re-authentication for privilege escalation. |

### A.7 Patching

| Setting | Resolved Value | Driving Framework |
|---|---|---|
| Critical vulnerability remediation | 30 days | PCI DSS, HITRUST Level 2 |
| High vulnerability remediation | 90 days | Industry standard |
| Medium vulnerability remediation | 180 days | Industry standard |
| Actively exploited zero-day | 72 hours (best effort) | HITRUST Threat Catalogue |

### A.8 Scanning

| Setting | Resolved Value | Driving Framework |
|---|---|---|
| File integrity check (AIDE) | Hourly | STIG |
| Package CVE check (vulnix) | Weekly | STIG, HITRUST |
| Nix store verification (`nix-store --verify`) | Daily | Operational |
| Full malware scan (ClamAV) | Weekly | PCI DSS Req 5 |
| Host hardening assessment (Lynis) | Monthly | HITRUST Level 2 |
| Internal network vulnerability scan (OpenVAS/Nessus) | Quarterly | PCI DSS Req 11.3.1 |
| PCI segmentation validation | Every 6 months | PCI DSS 11.4.5 |
| Compliance evidence snapshot | Weekly + on every `nixos-rebuild switch` | Operational |

### A.9 Encryption

| Setting | Resolved Value | Driving Framework | Conflict Resolved |
|---|---|---|---|
| TLS minimum version | TLS 1.2 | All frameworks | |
| TLS ciphers (Nginx) | `ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256` | HIPAA, NIST SC-8 | AEAD ciphers only. For strict FIPS: remove CHACHA20-POLY1305 entries. The HIPAA module's `HIGH:!aNULL:!MD5:!RC4` shorthand — **rejected** as it includes CBC-mode ciphers vulnerable to padding oracle attacks. |
| Disk encryption | LUKS2 with AES-256-XTS | All frameworks | |
| Swap encryption | LUKS-based encrypted swap via `boot.initrd.luks.devices` or `swapDevices` pointing to an already-opened LUKS device | HIPAA, PCI DSS | PCI module used deprecated `swapDevices.*.encrypted` (removed NixOS 23.11+) — **rejected**. Use LUKS-based swap. |

### A.10 Kernel Module Blacklist

The `stig-baseline` module maintains the canonical `boot.blacklistedKernelModules` list. No other module should declare this option.

```
# Canonical list — STIG (superset of all framework-specific lists)
boot.blacklistedKernelModules = [
  # Unnecessary filesystems
  "cramfs" "freevxfs" "jffs2" "hfs" "hfsplus" "squashfs" "udf"
  # Unnecessary network protocols
  "dccp" "sctp" "rds" "tipc"
  # Wireless (not applicable to server)
  "bluetooth" "btusb" "cfg80211" "mac80211"
  # FireWire / IEEE 1394
  "firewire-core" "firewire-ohci" "firewire-sbp2" "firewire-net"
  "ohci1394" "sbp2" "dv1394" "raw1394" "video1394"
  # Thunderbolt (DMA attack vector)
  "thunderbolt"
  # USB mass storage
  "usb-storage" "uas"
  # Miscellaneous
  "pcspkr" "snd_pcsp" "floppy"
];
```

**Driving framework:** STIG (comprehensive list). HIPAA required only `usb-storage` and `firewire-core`; PCI DSS added `uas`; HITRUST added `thunderbolt`. The STIG list is the superset.

### A.11 Filesystem Permissions (tmpfiles.rules)

The implementation flake consolidates all `systemd.tmpfiles.rules` in a single location. No module PRD should declare competing rules for the same path.

| Path | Mode | Owner | Group | Driving Framework | Conflict Resolved |
|---|---|---|---|---|---|
| `/var/lib/ollama` | `0750` | `ollama` | `ollama` | HIPAA, STIG | Consensus. |
| `/var/lib/agent-runner` | `0750` | `agent` | `agent` | HIPAA, STIG | Consensus. |
| `/var/lib/agent-runner/workspace` | `0750` | `agent` | `agent` | OWASP | Ephemeral; cleaned on service restart. |
| `/var/lib/ai-services` | `0750` | `ai-services` | `ai-services` | HIPAA | |
| `/var/lib/ai-services/rag` | `0750` | `ai-services` | `ai-services` | HIPAA | |
| `/var/log/audit` | `0700` | `root` | `root` | STIG | HIPAA used `root:audit` — **STIG's stricter root-only access prevails**. |
| `/var/log/ai-audit` | `0700` | `root` | `root` | HIPAA, STIG | Consistent with `/var/log/audit`. |
| `/var/log/sudo-io` | `0700` | `root` | `root` | STIG | |
| `/var/lib/compliance-evidence` | `0750` | `root` | `root` | Operational | Evidence snapshots directory. |

### A.12 AIDE Monitored Paths

AIDE must monitor NixOS-correct paths. Traditional Linux paths (`/usr/bin`, `/sbin`, `/usr/lib`) are empty or nonexistent on NixOS and must not be used.

| Path | AIDE Rule | Purpose |
|---|---|---|
| `/run/current-system/sw/bin` | `R+sha512` | System binaries (NixOS equivalent of `/usr/bin`) |
| `/run/current-system/sw/sbin` | `R+sha512` | System admin binaries |
| `/etc` | `R+sha512` | System configuration |
| `/boot` | `R+sha512` | Bootloader and kernel |
| `/var/lib/ollama/models` | `R+sha256` | Model artifact integrity |
| `/var/lib/ai-services` | `R+sha512` | Application data integrity |
| `/nix/var/nix/profiles/system` | `R+sha512` | NixOS generation symlink (detects rebuilds) |

**Do not monitor:** `/usr/bin`, `/usr/sbin`, `/sbin`, `/usr/lib` — these paths do not exist on NixOS. Monitoring them produces noise and misses actual binaries.

### A.13 FIPS Mode Decision

| Setting | Resolved Value | Notes |
|---|---|---|
| FIPS enforcement mode | **Algorithm-compatible, not FIPS-validated** | NixOS does not ship a FIPS-validated OpenSSL module. The `fips=yes` OpenSSL config — **do not use** without a loaded FIPS provider (breaks OpenSSL entirely). SSH and TLS ciphers are restricted to FIPS-approved algorithms (AES-GCM, AES-CTR, SHA-2) but the implementation is not FIPS 140-2/3 validated. Document this as a known gap per STIG Section 11. |
| Ed25519 SSH keys | Allowed (not FIPS-approved but used by default) | For strict FIPS: use ECDSA-P256 or RSA-4096 instead. For most deployments, Ed25519 is acceptable with documented exception. |

### A.14 NixOS-Specific Options

These NixOS options are frequently referenced across modules. Each must be set exactly once in the implementation flake.

| Option | Resolved Value | Module Owner | Notes |
|---|---|---|---|
| `users.mutableUsers` | `false` | `stig-baseline` | All accounts declared in config only. |
| `nix.settings.allowed-users` | `[ "admin" ]` | `stig-baseline` | HITRUST used `[ "@wheel" ]`, another section used `[ "root" "admin" ]` — **resolved to named user**. `@wheel` is acceptable as alternative. |
| `boot.loader.systemd-boot.editor` | `false` | `stig-baseline` | Prevent boot parameter modification. |
| `systemd.ctrlAltDelUnit` | `""` | `stig-baseline` | Disable Ctrl-Alt-Del reboot. |
| `systemd.coredump.extraConfig` | `"Storage=none"` | `stig-baseline` | Disable core dumps (ePHI/CHD in memory). |
| `boot.kernel.sysctl."kernel.core_pattern"` | `"\|/bin/false"` | `stig-baseline` | Kernel-level core dump redirect. |
| `networking.wireless.enable` | `false` | `lan-only-network` | No wireless on server. |
| `services.xserver.enable` | `false` | `stig-baseline` | Headless server; no GUI. |

### A.15 Notify/Alert Service Template

The `notify-admin@` template unit uses systemd specifiers, not shell variables.

```
# Correct: use %i for the instance name
ExecStart = writeShellScript "notify-admin" ''
  MONITOR_UNIT="%i"
  echo "[ALERT] Service $MONITOR_UNIT failed at $(date)" >> /var/log/admin-alerts.log
'';
```

**Do not use `$1`** — this is a shell positional parameter, not a systemd specifier. The NIST module's original `$1` usage was incorrect and has been corrected.
