# AI Governance Overview

Three frameworks for AI-specific governance: NIST AI RMF, EU AI Act, ISO 42001.

## NIST AI Risk Management Framework

Four functions forming a continuous lifecycle:

### GOVERN — Organizational Context
- Written AI risk management policy (annual review)
- Role separation: System Owner, Operator, Security Engineer, Data Steward
- Enforced via distinct NixOS system accounts (ai-admin, ai-operator, agent, ollama)

### MAP — Context and Risk Identification
- Deployment context: on-premises, LAN-only, open-weight LLMs
- Each model needs documented intended-use statement in model registry
- Risk identification: hallucination, prompt injection, backdoors, sandbox escape, data leakage

### MEASURE — Testing and Monitoring
- Pre-deployment: functional testing, adversarial prompts, bias assessment, performance baseline
- Ongoing: inference latency, error rate, agent completion, model integrity, GPU utilization
- Health checks every 5 minutes via systemd timer (NOT WatchdogSec — see [[../nixos-platform/nixos-gotchas]])

### MANAGE — Risk Treatment and Response
- Four AI-specific incident types: harmful outputs, agent exceeding auth, model compromise, prompt injection
- Emergency kill switch: `ai-emergency-stop` script
- Quarterly reviews, post-incident within 5 business days

## EU AI Act

### Risk Classification (by use case, not architecture)
- Code assistance / doc summarization → Minimal risk
- RAG over internal KB → Limited risk (transparency requirement)
- Agent operational decisions → Potentially high risk
- Health data processing → High risk

### Key Requirements (High-Risk)
- **Article 11:** Technical documentation baked into build as `/etc/ai/system-description.json`
- **Article 12:** Structured per-request inference logging — **Ollama can't do this**; app layer must
- **Article 14:** Human oversight — approval gates, kill switch, fail-closed design
- **Article 15:** Robustness — timer-based health monitoring, rate limiting, rollback
- **Article 13:** Transparency — X-AI-Generated headers in API responses

### Critical Ollama Limitation
Ollama produces unstructured service logs, NOT structured per-request records. The application layer on port 8000 **must** produce structured inference audit records for Article 12 compliance.

## ISO/IEC 42001

Key Annex A control areas:
- A.2: AI Policies + acceptable use
- A.3: Internal organization + role separation
- A.5: Impact assessment
- A.6: AI system lifecycle (design through retirement)
- A.7: Data quality, provenance, preparation
- A.9: Intended use, human oversight, user monitoring
- A.10: Third-party/supplier relationships

### RAG Data Governance (A.6.2)
- Document lineage tracking for every ingested document
- Embedding store versioning (model identity, corpus version)
- Quality metrics: retrieval precision >80% at k=5
- Document retention: removed from source → removed from corpus

## Key Takeaways

- AI governance scope depends on use case classification, not system architecture
- The three frameworks overlap heavily — implement once via [[tiered-implementation]]
- Ollama's logging limitation is a real compliance gap — app-layer middleware is required
- [[model-supply-chain]] is a critical dependency for all three frameworks
