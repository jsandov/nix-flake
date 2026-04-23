# Threat Model

Defines what the system protects, who the adversaries are, and scope boundaries.

## Protected Assets

- Model artifacts (weights, configs)
- Inference prompts and responses
- Agent actions and tool invocations
- Audit logs and compliance evidence
- Sensitive data: ePHI, CHD, PII processed through the AI pipeline

## Adversary Model

| Adversary | Description |
|---|---|
| External LAN attacker | Compromised device on the same network |
| Malicious input data | Prompt injection, poisoned documents |
| Compromised model weights | Supply chain attack on model provider |
| Insider | Unprivileged local account holder |

## Excluded Threats

- Nation-state with physical access
- Hardware implants
- Side-channel attacks on CPU/GPU
- Compromised NixOS upstream infrastructure

## Primary Risk

Unauthorized access to sensitive data via the AI inference pipeline — through direct network access, prompt injection, agent tool misuse, or log contamination.

## Scope Boundaries

**In scope (implemented by the flake):**
- All OS-level, network-level, and service-level technical controls
- Agent runtime isolation and tool restrictions
- Audit logging, integrity monitoring, evidence generation
- Encryption at rest and in transit
- Model provenance verification

**Requires complementary measures:**
- Administrative policies, workforce training, governance docs
- Physical security
- Business associate agreements, data processing contracts
- Risk assessments, privacy impact assessments
- Application-layer prompt injection defenses — see [[ai-security-residual-risks]]
- Human review for AI outputs in high-risk decisions

## Design Philosophy

Implement every technical control possible at host and service layer, document what remains, provide hooks for organizational processes.

## Key Takeaways

- This is a **single-tenant, single-operator** system on dedicated hardware — not multi-user or clustered
- LAN-only posture limits the attacker pool but doesn't eliminate risk
- The biggest residual risk is [[hipaa/live-memory-ephi-risk|live memory ePHI exposure]] during inference
- ~60% of [[ai-security/owasp-llm-top-10|OWASP controls]] require application code, not just infrastructure
