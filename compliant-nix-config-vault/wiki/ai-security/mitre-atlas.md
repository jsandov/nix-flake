# MITRE ATLAS

Adversarial Threat Landscape for AI Systems — technique-to-mitigation mapping.

## Technique Matrix

| ATLAS ID | Technique | Primary Mitigation | Module |
|---|---|---|---|
| AML.T0010 | ML Supply Chain Compromise | Hash verification, trusted sources, AIDE | ai-services, audit-and-aide |
| AML.T0015 | Evade ML Model | Input validation, adversarial testing | Application layer |
| AML.T0018 | Backdoor ML Model | Provenance, behavioral testing | ai-services |
| AML.T0024 | Exfiltration via Inference API | FDE, permissions, LAN-only, SSH hardening | stig-baseline, lan-only-network |
| AML.T0040 | Inference API Abuse | Rate limiting, auth, resource limits | ai-services, lan-only-network |
| AML.T0043 | Craft Adversarial Data | Sandbox, approval gates, output review | agent-sandbox |
| AML.T0051 | LLM Prompt Injection | Input validation, no egress, tool allowlist | agent-sandbox, lan-only-network |
| AML.T0056 | LLM Data Leakage | Output logging, network isolation, classification | agent-sandbox, audit-and-aide |

## Key Mitigations by Attack Vector

### Model Supply Chain (T0010, T0018)
- Model registry with expected hashes
- AIDE hourly integrity checks on model directory
- Behavioral testing post-download
- **Limitation:** trust-on-first-download only

### Data Exfiltration (T0024, T0051, T0056)
- LAN-only firewall (no internet egress from services)
- Per-UID egress filtering via nftables
- Agent IPAddressDeny="any" with loopback allowlist only
- Full-disk encryption protects at rest

### API Abuse (T0040)
- Rate limiting (≤30 req/min/client)
- Application-layer authentication
- systemd resource limits (MemoryMax, CPUQuota)
- Usage logging with source IP and token count

## Important Note

ATLAS technique IDs are actively reorganized across releases. The mappings in this document should be **verified quarterly** against the current ATLAS knowledge base at https://atlas.mitre.org.

## Key Takeaways

- LAN-only posture is the strongest single mitigation — eliminates most exfiltration paths
- Model integrity monitoring via AIDE catches post-deployment tampering
- Supply chain provenance is the weakest link — Ollama has no cryptographic attestation
- See [[../ai-governance/model-supply-chain]] for the full download-to-deploy pipeline
