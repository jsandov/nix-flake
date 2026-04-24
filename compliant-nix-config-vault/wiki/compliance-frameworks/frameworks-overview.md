# Frameworks Overview

Ten compliance frameworks mapped to the NixOS flake, each with a dedicated PRD module.

## The Frameworks

| Framework | Scope | Key Focus |
|---|---|---|
| **NIST SP 800-53 Rev 5** | All 20 control families | Moderate baseline, comprehensive federal controls |
| **HIPAA** | Security, Privacy, Breach Notification Rules | ePHI protection — see [[../hipaa/]] |
| **HITRUST CSF v11** | 19 control domains (corrected from PRD's 14; see [[hitrust-corrections]]) | Healthcare maturity model |
| **PCI DSS v4.0** | 12 requirements for CDE security | Payment card data — see [[../pci-dss/]] |
| **OWASP Top 10 for LLMs** | LLM + agentic AI threats | AI-specific vulnerabilities — see [[../ai-security/]] |
| **NIST AI RMF** | Govern, Map, Measure, Manage | AI risk lifecycle — see [[../ai-governance/]] |
| **EU AI Act** | High-risk AI technical requirements | Regulatory compliance for AI |
| **ISO 42001** | AI management system controls | AI governance standard |
| **MITRE ATLAS** | Adversarial threat landscape for AI | Threat modeling — see [[../ai-security/mitre-atlas]] |
| **STIG / DISA** | NixOS STIG findings | DoD hardening expectations |

## Framework Conflicts Are Real

Multiple frameworks impose different requirements for the same setting:

| Setting | Strictest Value | Winner |
|---|---|---|
| Log retention | 365 days (journal) | PCI DSS |
| Password min length | 15 chars | STIG/HITRUST |
| Patch timeline (critical) | 30 days | PCI DSS/HITRUST |
| Account lockout | 5 attempts, 30 min | STIG/HITRUST |
| Session timeout | 600s | STIG |

All conflicts are resolved in [[canonical-config-values]] — the implementation flake uses ONLY those values.

## Key Takeaways

- Each framework has its own PRD module; the master PRD is the umbrella
- Framework overlap is extensive — most controls satisfy 3-5 frameworks simultaneously
- Conflicts are resolved toward the strictest applicable requirement
- [[../nixos-platform/compliance-advantages|NixOS structural properties]] make several traditionally difficult controls trivially enforceable
