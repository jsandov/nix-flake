# Cross-Framework Control Matrix

Which [[../architecture/flake-modules|flake modules]] implement controls for which frameworks.

## Module-to-Framework Mapping

Status legend: **shipped** = real module code on `main`; **[stub]** = comment-only scaffold; behaviour planned in `todos/`.

### Foundation modules (declare typed options; shipped)

| Flake Module | NIST 800-53 | HIPAA | HITRUST | PCI DSS | OWASP | AI Gov | STIG | Status |
|---|---|---|---|---|---|---|---|---|
| `canonical` | All (single source of truth) | Access, Audit, Auth | Access, Config | Req 2,3,5,6,8,10 | — | — | Resolved values | shipped |
| `meta` | PM, RA, SA | Risk analysis | Risk mgmt | Req 12 (policy) | Threat model | Foundation | Scope declaration | shipped |
| `secrets` | SC, IA, AC | Access control, integrity | Cryptography | Req 3, 8 | Secret management | Model registry auth | Key management | shipped |
| `accounts` | AC-2, IA-2, IA-5 | §164.308(a)(3-4) | 01.* (Access Control) | Req 7, 8 | — | — | Account management | shipped |

### Behaviour-owning modules

| Flake Module | NIST 800-53 | HIPAA | HITRUST | PCI DSS | OWASP | AI Gov | STIG | Status |
|---|---|---|---|---|---|---|---|---|
| `stig-baseline` | AC, IA, CM, SC, SI | Access, Audit, Auth | Access, Config | Req 2,5,6,8 | Reduced surface | Foundation | Primary | shipped |
| `audit-and-aide` | AU, CM, SI, IR | Audit, Integrity | Audit, Monitor | Req 10,11,12 | Abuse detection | Monitoring | Audit/drift | shipped (AIDE deferred to INFRA-09) |
| `gpu-node` | CM, SA, SI | Integrity | Asset, Config | Req 6 | Runtime integrity | Model deploy | Exceptions | **[stub]** (AI-10) |
| `lan-only-network` | AC, SC, CA | Transmission | Network | Req 1, 4 | Tool misuse | Network isolation | Boundary | **[stub]** (module code future; PRD prose landed via INFRA-01/02) |
| `agent-sandbox` | AC, SC, SI, AU | Min Necessary | Access, Risk | Req 7, 8 | Sandboxing | Agent risk | Process isolation | **[stub]** (AI-08) |
| `ai-services` | AC, SC, SI, AU | ePHI, Encryption | Data, Crypto | Req 3, 4, 8 | Prompt injection | Model governance | Hardening | **[stub]** (AI-09) |

## Control Coverage by Priority

### Critical — Before Production
- AC (Access Control), SC (System/Comms Protection), AU (Audit), SI (Integrity), IA (Authentication), CM (Config Mgmt)

### High — First Iteration
- MP (Media Protection), MFA, defense in depth, supply chain integrity, vulnerability scanning

### Medium — Second Iteration
- IR (Incident Response), CP (Contingency Planning), SA (Acquisition), MA (Maintenance)

### Low — Organizational/Documentation
- AT (Training), PE (Physical), PL (Planning), PM (Program Mgmt), PS (Personnel)

## Key Takeaways

- `canonical` + `meta` + `secrets` + `accounts` are the four foundation modules; every framework-mapping value flows through them.
- `stig-baseline` + `audit-and-aide` are the first real behaviour modules; both consume `canonical` extensively.
- `audit-and-aide` provides the evidence backbone for all framework audits; `services.complianceEvidence.collectors` is the extension point for framework-specific evidence (first consumer: `accounts.accessReview`).
- `agent-sandbox` is the planned primary defense for [[../ai-security/owasp-llm-top-10|OWASP AI threats]] — still a stub; see the AI-08 TODO.
- Most controls satisfy multiple frameworks simultaneously — build once, comply many.
