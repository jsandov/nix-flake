# AI Governance Frameworks — NIST AI RMF, EU AI Act, ISO 42001

Source: prd-ai-governance.md

## NIST AI Risk Management Framework (AI 100-1)

Four functions: GOVERN → MAP → MEASURE → MANAGE

### GOVERN
- AI risk management policy required (written, annual review)
- Role separation: AI System Owner, AI Operator, Security Engineer, Data Steward
- Technical enforcement via distinct NixOS system accounts
- Governance culture: annual AI risk awareness training

### MAP
- Context mapping: on-premises, single host, LAN-only, open-weight LLMs
- Each model needs documented intended-use statement
- Model registry as `/etc/ai/model-registry.json` in flake
- Risk identification table: hallucination, prompt injection, backdoors, sandbox escape, data leakage

### MEASURE
- Pre-deployment: functional testing, safety testing, bias assessment, performance baseline
- Ongoing metrics: inference latency, error rate, agent completion rate, model integrity, GPU utilization
- Health check every 5 minutes via systemd timer (NOT WatchdogSec — Ollama doesn't support sd_notify)

### MANAGE
- Risk treatment for each identified risk
- AI-specific incident types: harmful outputs, agent exceeding auth, model compromise, prompt injection
- Emergency kill switch: `ai-emergency-stop` script
- Quarterly reviews, post-incident within 5 business days

## EU AI Act

### Risk Classification (depends on use case, not architecture)
- Internal code assistance → Minimal risk
- Document summarization → Minimal risk
- RAG over internal KB → Limited risk (transparency)
- Agent operational decisions → Potentially high risk
- Health data processing → High risk

### Key Requirements for High-Risk
- **Article 11 (Technical Documentation):** System description metadata baked into build
- **Article 12 (Record-Keeping):** Structured per-request inference logging (Ollama doesn't do this — app layer must)
- **Article 14 (Human Oversight):** Approval gates, kill switch, override mechanisms, fail-closed design
- **Article 15 (Accuracy/Robustness/Cybersecurity):** Pre-deployment validation, timer-based health monitoring, rate limiting
- **Article 13 (Transparency):** Users must know they interact with AI, X-AI-Generated headers

### Critical: Ollama Logging Limitation
Ollama produces unstructured service logs, NOT structured per-request records. The application layer on port 8000 **must** produce structured inference audit records for Article 12 compliance.

## ISO/IEC 42001

Annex A control areas mapped:
- A.2: AI Policies
- A.3: Internal Organization (role separation)
- A.4: Resources (compute, data, human, infrastructure)
- A.5: Impact Assessment
- A.6: AI System Lifecycle (design through retirement)
- A.7: Data for AI Systems (quality, provenance, preparation)
- A.8: Information for Interested Parties (transparency, incident reporting)
- A.9: Use of AI Systems (intended use, human oversight)
- A.10: Third-Party/Supplier Relationships

### RAG Data Governance (A.6.2 / EU AI Act Article 10)
- Document lineage tracking (source, timestamp, preprocessing, authorizer)
- Embedding store versioning (model identity, dimensions, corpus version)
- Quality metrics: retrieval precision >80% at k=5, recall >70% at k=10
- Document retention: removed from source → removed from corpus within retention window

## Tiered Implementation Guide

**Tier 1 — Single operator, internal, low-risk** (5 processes)
- AI risk policy, acceptable use, model classification, pre-deployment testing, data governance

**Tier 2 — Small team, sensitive data, medium-risk** (11 processes)
- Add: accountability, training, intended-use docs, incident response, post-incident review, retirement

**Tier 3 — Full compliance, high-risk, regulated** (all 17 processes)
- Add: bias assessment, quarterly reviews, supplier assessment, license compliance, transparency, regulatory contacts

## Model Supply Chain Security

### Provenance Limitation
Ollama has no GPG signatures, SLSA provenance, or cryptographic attestation. Verification is hash-comparison against locally-maintained manifest. Trust-on-first-download.

### Model Manifest Required Fields
name, provider, version, source_url, hash, license, license_compliant_uses, known_limitations, known_biases, risk_tier, intended_use, deployment_date, review_due, validation_results_path

### Deployment Pipeline
Request → Fetch + Hash Verify → Validate (functional + adversarial) → Register → Deploy (nixos-rebuild) → Monitor (AIDE + health checks)

### Ollama Storage Format
Models stored as **content-addressed blobs** in `/var/lib/ollama/models/blobs/sha256-<hex>`. Not `.bin` files. Manifest files in `/var/lib/ollama/models/manifests/` list layer digests.
