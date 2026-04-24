# Cross-Framework Control Matrix

Which [[../architecture/flake-modules|flake modules]] implement controls for which frameworks.

## Module-to-Framework Mapping

| Flake Module | NIST 800-53 | HIPAA | HITRUST | PCI DSS | OWASP | AI Gov | STIG |
|---|---|---|---|---|---|---|---|
| `stig-baseline` | AC, IA, CM, SC, SI | Access, Audit, Auth | Access, Config | Req 2,5,6,8 | Reduced surface | Foundation | Primary |
| `gpu-node` | CM, SA, SI | Integrity | Asset, Config | Req 6 | Runtime integrity | Model deploy | Exceptions |
| `lan-only-network` | AC, SC, CA | Transmission | Network | Req 1, 4 | Tool misuse | Network isolation | Boundary |
| `audit-and-aide` | AU, CM, SI, IR | Audit, Integrity | Audit, Monitor | Req 10,11,12 | Abuse detection | Monitoring | Audit/drift |
| `agent-sandbox` | AC, SC, SI, AU | Min Necessary | Access, Risk | Req 7, 8 | Sandboxing | Agent risk | Process isolation |
| `ai-services` | AC, SC, SI, AU | ePHI, Encryption | Data, Crypto | Req 3, 4, 8 | Prompt injection | Model governance | Hardening |

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

- `stig-baseline` touches the most frameworks — it's the foundation everything builds on
- `audit-and-aide` provides the evidence backbone for all framework audits
- `agent-sandbox` is the primary defense for [[../ai-security/owasp-llm-top-10|OWASP AI threats]]
- Most controls satisfy multiple frameworks simultaneously — build once, comply many
