# HITRUST Corrections

Issues found in the original HITRUST PRD and the corrected understanding.

## Domain Taxonomy Fix

The original PRD used 14 domains. HITRUST CSF v11 actually has **19 domains** (numbered 00-18):

| # | Domain |
|---|---|
| 00 | Information Security Management Program |
| 01 | Access Control |
| 02 | Human Resources Security |
| 03 | Risk Management |
| 04 | Security Policy |
| 05 | Organization of Information Security |
| 06 | Compliance |
| 07 | Asset Management |
| 08 | Physical and Environmental Security |
| 09 | Communications and Operations Management |
| 10 | Information Systems Acquisition, Development, and Maintenance |
| 11 | Information Security Incident Management |
| 12 | Business Continuity Management |
| 13 | Privacy Practices |
| 14-18 | Additional v11 domains |

Work from MyCSF, not summary documents. Map to MyCSF requirement statement IDs (format: "19748v2") once assessment scope is finalized.

## Assessment Tiers

| Tier | Statements | This System's Target |
|---|---|---|
| e1 (Essentials) | 44 | Fully met by flake config |
| i1 (Implemented) | 219 | Primary target — all technical controls in Nix |
| r2 (Risk-based) | 2000+ | Stretch — needs external assessor + policy docs |

The i1 control set is updated by the **HITRUST Threat Catalogue** between assessment cycles. Review current Threat Catalogue during preparation.

## Maturity Level Constraints

| Year | Maximum Achievable | What It Means |
|---|---|---|
| Year 1 | Level 3 (Implemented) | Controls deployed and operating |
| Year 2 | Level 4 (Measured) | Quarterly metrics, management reviews, trend analysis |
| Year 3+ | Level 5 (Managed) | Continuous improvement driven by measurement data |

**Level 5 in Year 1 is not credible** — assessors will flag it immediately. Having auditd running is Level 3. Having quarterly metric reports with tuning evidence reviewed by management is Level 4. Level 5 requires demonstrated improvement actions across multiple review cycles.

## Alternate Controls vs Compensating Controls

HITRUST uses **"alternate controls"** (not "compensating controls" — that's PCI DSS terminology). Alternate control requests must be submitted formally through the MyCSF portal during assessment.

## Key Takeaways

- The original PRD's biggest weakness (scored 6.1/10) — wrong domain count and unrealistic maturity claims
- Work from MyCSF portal, not summaries or secondary sources
- Don't claim Level 4+ maturity in Year 1 for any domain
- The NixOS declarative model is a natural fit for HITRUST — configuration IS documentation IS evidence
- See [[review-findings/master-review]] for the full scoring breakdown
