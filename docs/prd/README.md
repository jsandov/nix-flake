# Product Requirements Documents

PRD suite for the compliance-mapped NixOS AI agentic server. These documents define requirements — the implementation lives in the NixOS flake.

## Documents

| Document | Description |
|---|---|
| [prd.md](prd.md) | **Master PRD** — architecture, shared requirements, cross-framework matrix, canonical config values (Appendix A) |
| [prd-nist-800-53.md](prd-nist-800-53.md) | NIST SP 800-53 Rev 5 — all 20 control families |
| [prd-hipaa.md](prd-hipaa.md) | HIPAA Security Rule, Privacy Rule, Breach Notification Rule |
| [prd-hitrust.md](prd-hitrust.md) | HITRUST CSF v11 — control domains |
| [prd-pci-dss.md](prd-pci-dss.md) | PCI DSS v4.0 — all 12 requirements |
| [prd-owasp.md](prd-owasp.md) | OWASP Top 10 for LLMs + Agentic AI threats |
| [prd-ai-governance.md](prd-ai-governance.md) | NIST AI RMF, EU AI Act, ISO 42001, MITRE ATLAS |
| [prd-stig-disa.md](prd-stig-disa.md) | STIG / DISA hardening expectations |
| [MASTER-REVIEW.md](MASTER-REVIEW.md) | Expert review — scores, systemic issues, action plan |

## Reading Order

1. Start with **prd.md** for architecture and shared requirements
2. Read **MASTER-REVIEW.md** for known issues and the action plan
3. Dive into framework-specific modules as needed
4. Always check **prd.md Appendix A** for resolved canonical config values
