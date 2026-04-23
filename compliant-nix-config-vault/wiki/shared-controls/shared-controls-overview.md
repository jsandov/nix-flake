# Shared Controls Overview

Sixteen controls demanded by multiple frameworks, implemented once in the appropriate [[architecture/flake-modules|flake module]].

## Core Controls

| # | Control | Module Owner | Frameworks |
|---|---|---|---|
| 1 | Full-Disk Encryption (LUKS2 AES-256-XTS) | stig-baseline | NIST SC-28, HIPAA, PCI Req 3, HITRUST, STIG |
| 2 | SSH Hardening (key-only + MFA) | stig-baseline | All frameworks |
| 3 | Audit Logging (auditd + journald) | audit-and-aide | All frameworks |
| 4 | NTP Synchronization (Chrony) | audit-and-aide | NIST AU-8, PCI Req 10, HIPAA, STIG |
| 5 | File Integrity Monitoring (AIDE) | audit-and-aide | NIST SI-7, PCI Req 11, HIPAA, STIG |
| 6 | Egress Filtering | lan-only-network | NIST SC-7, PCI Req 1, OWASP |
| 7 | Agent Sandboxing (systemd) | agent-sandbox | OWASP Agentic, all frameworks (least privilege) |
| 8 | Model Provenance Verification | ai-services | MITRE ATLAS, NIST AI RMF, EU AI Act |
| 9 | [[evidence-generation]] | audit-and-aide | All frameworks |
| 10 | Incident Response Hooks | audit-and-aide | NIST IR, HIPAA, PCI Req 12, HITRUST |
| 11 | Backup and Recovery | stig-baseline | NIST CP, HIPAA, PCI Req 12, HITRUST |
| 12 | Vulnerability Management | stig-baseline | NIST RA/SI, PCI Req 6, HIPAA, STIG |
| 13 | [[secrets-management]] | stig-baseline | All frameworks |
| 14 | Boot Integrity (UEFI Secure Boot) | stig-baseline | STIG, NIST SI-7 |
| 15 | Account Lifecycle Management | stig-baseline | All frameworks |
| 16 | Data Classification (4 levels) | All | All frameworks |

## Data Classification Scheme

| Level | Label | Examples | Handling |
|---|---|---|---|
| 1 | Public | Published model metadata | Integrity only |
| 2 | Internal | Inference logs, system config | Encrypted at rest, restricted access |
| 3 | Sensitive | ePHI, CHD, PII | Encrypted everywhere, audit-logged, masked in logs |
| 4 | Restricted | LUKS keys, age keys, TLS keys, TOTP seeds | sops-nix only, never plaintext, never in Nix store |

## Key Takeaways

- Most controls satisfy 3-5 frameworks simultaneously — build once, comply many
- Agent sandboxing is the primary mitigation for [[ai-security/owasp-agentic-threats]]
- Evidence generation runs weekly + on every rebuild — see [[evidence-generation]]
- Vulnerability management timelines: Critical 30d, High 90d, Medium 180d — see [[compliance-frameworks/canonical-config-values]]
