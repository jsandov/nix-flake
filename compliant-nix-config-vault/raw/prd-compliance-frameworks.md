# Compliance Frameworks — 10 Frameworks Mapped

Source: prd.md, all framework-specific PRD modules

## The Ten Frameworks

| Framework | Scope | PRD Module |
|---|---|---|
| NIST SP 800-53 Rev 5 | All 20 control families | prd-nist-800-53.md |
| HIPAA | Security Rule, Privacy Rule, Breach Notification | prd-hipaa.md |
| HITRUST CSF v11 | All 14 control domains | prd-hitrust.md |
| PCI DSS v4.0 | All 12 requirements for CDE security | prd-pci-dss.md |
| OWASP Top 10 for LLMs | LLM-specific + Agentic AI threats | prd-owasp.md |
| NIST AI RMF | AI risk lifecycle (Govern, Map, Measure, Manage) | prd-ai-governance.md |
| EU AI Act | High-risk AI system technical requirements | prd-ai-governance.md |
| ISO 42001 | AI management system controls | prd-ai-governance.md |
| MITRE ATLAS | Adversarial threat landscape for AI | prd-ai-governance.md |
| STIG / DISA | NixOS STIG findings and DISA hardening | prd-stig-disa.md |

## Cross-Framework Control Matrix

| Flake Module | NIST 800-53 | HIPAA | HITRUST | PCI DSS | OWASP | AI Gov | STIG |
|---|---|---|---|---|---|---|---|
| stig-baseline | AC, IA, CM, SC, SI | Access, Audit, Auth | Access, Config | Req 2,5,6,8 | Reduced surface | Foundation | Primary |
| gpu-node | CM, SA, SI | Integrity | Asset, Config | Req 6 | Runtime integrity | Model deploy | Driver exceptions |
| lan-only-network | AC, SC, CA | Transmission | Network | Req 1, 4 | Tool misuse | Network isolation | Boundary |
| audit-and-aide | AU, CM, SI, IR | Audit, Integrity | Audit, Monitor | Req 10,11,12 | Abuse detection | Monitoring | Audit/drift |
| agent-sandbox | AC, SC, SI, AU | Min Necessary, Access | Access, Risk | Req 7, 8 | Sandboxing | Agent risk | Process isolation |
| ai-services | AC, SC, SI, AU | ePHI, Encryption | Data, Crypto | Req 3, 4, 8 | Prompt injection | Model governance | Service hardening |

## Key Learning: Framework Conflicts Are Real

Multiple frameworks impose different requirements for the same setting:

| Setting | NIST | HIPAA | HITRUST | PCI DSS | STIG |
|---|---|---|---|---|---|
| Log retention | 90 days | 6yr (docs) | 1 year | 1yr (3mo avail) | 90 days |
| Password min length | "appropriate" | — | 15 chars | 12 chars | 15 chars |
| Patch timeline | "timely" | "reasonable" | 15-30 days | 30 days | per ATO |
| MFA scope | privileged | addressable | Level 2+ | all CDE | privileged remote |

**Resolution:** Always resolve toward the strictest applicable requirement. The master PRD Appendix A is the canonical source of truth for all resolved values.

## NixOS as a Compliance Platform — Why It Works

1. **Declarative state (CM-2, CM-6)** — entire config is code, no configuration drift
2. **Immutable store (SI-3, SI-7)** — read-only, content-addressed, built-in tamper detection
3. **Atomic upgrades and rollback (CP-10, SI-2)** — instant rollback, no partial updates
4. **Reproducible builds (CM-2, SA-10)** — same inputs = same system
5. **No user-installed software (CM-11)** — only declared packages exist
6. **Garbage collection (MP-6)** — deterministic removal of old software

These properties mean several traditionally difficult controls are **structurally enforced** by the OS design rather than add-on tooling.
