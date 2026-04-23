# Tiered Implementation Guide

Three tiers for organizational AI governance processes — scope depends on deployment context.

## Tier 1 — Single Operator, Internal, Low-Risk (5 processes)

**Implement:** Risk policy, acceptable use, model classification, pre-deployment testing, data governance

**Use cases:** Personal productivity AI, internal dev tooling, experimentation with open-weight models, LAN-only inference with no sensitive data.

**Sufficient when:** Single person running local inference for their own use. No sensitive data. No consequential decisions.

## Tier 2 — Small Team, Sensitive Data, Medium-Risk (11 processes)

**Add to Tier 1:** Role assignment, training, intended-use docs, incident response, post-incident review, model retirement

**Use cases:** Team-shared AI services, RAG over internal knowledge bases, agent workflows with tool access, sensitive but non-regulated data.

**Mandatory escalation triggers:**
- Processing ePHI, PII, financial data, or regulated data
- Agent workflows can modify production systems
- AI outputs influence decisions affecting people

## Tier 3 — Full Compliance, High-Risk, Regulated (all 17 processes)

**Add to Tier 2:** Bias assessment, quarterly reviews, supplier assessment, license compliance, transparency, regulatory contacts

**Use cases:** Health data (ePHI), regulated domains, EU AI Act high-risk classification, external audit/regulatory inspection, ISO 42001 certification.

## Decision Tree

1. Any use case high-risk under EU AI Act Annex III? → **Tier 3**
2. Processing ePHI, GDPR PII, or regulated financial data? → **Minimum Tier 2, likely Tier 3**
3. Multiple users depend on the system? → **Minimum Tier 2**
4. Agent workflows modify production or affect people? → **Minimum Tier 2**
5. Single operator, personal internal use only? → **Tier 1**

## The 17 Organizational Processes

| ID | Process | Tier |
|---|---|---|
| AI-ORG-01 | AI risk management policy | 1 |
| AI-ORG-02 | Acceptable use policy | 1 |
| AI-ORG-03 | Role assignment and accountability | 2 |
| AI-ORG-04 | AI risk awareness training | 2 |
| AI-ORG-05 | Model risk classification | 1 |
| AI-ORG-06 | Intended-use documentation | 2 |
| AI-ORG-07 | Bias assessment | 3 |
| AI-ORG-08 | Pre-deployment testing | 1 |
| AI-ORG-09 | AI incident response procedure | 2 |
| AI-ORG-10 | Post-incident review | 2 |
| AI-ORG-11 | Quarterly AI risk review | 3 |
| AI-ORG-12 | Supplier assessment | 3 |
| AI-ORG-13 | License compliance | 3 |
| AI-ORG-14 | Data governance | 1 |
| AI-ORG-15 | Model retirement procedure | 2 |
| AI-ORG-16 | Transparency disclosure | 3 |
| AI-ORG-17 | Regulatory contact maintenance | 3 |

## Key Takeaways

- Don't try to implement all 17 processes on day one — start at the right tier
- Tier 1 is achievable by a single operator in a day
- Tier 2 is the sweet spot for most team deployments
- Tier 3 is mandatory if regulated data or high-risk AI classification applies
- Review tier selection when use cases change or new models are deployed
