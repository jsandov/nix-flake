# Compliant NixOS AI Server

A compliance-mapped NixOS flake for a LAN-only, hardened AI server with local GPU inference and sandboxed agentic workflows. Every technically-enforceable control from 10 regulatory and security frameworks is implemented declaratively through NixOS modules.

## Repository Structure

```
nix-flake/
├── docs/
│   └── prd/                        # Product Requirements Documents
│       ├── README.md               # Document index and reading order
│       ├── prd.md                  # Master PRD — architecture, canonical config (Appendix A)
│       ├── prd-nist-800-53.md      # NIST SP 800-53 Rev 5
│       ├── prd-hipaa.md            # HIPAA Security/Privacy/Breach Rules
│       ├── prd-hitrust.md          # HITRUST CSF v11
│       ├── prd-pci-dss.md          # PCI DSS v4.0
│       ├── prd-owasp.md            # OWASP Top 10 for LLMs + Agentic AI
│       ├── prd-ai-governance.md    # NIST AI RMF, EU AI Act, ISO 42001, MITRE ATLAS
│       ├── prd-stig-disa.md        # STIG / DISA hardening
│       └── MASTER-REVIEW.md        # Expert review — scores and action plan
│
└── compliant-nix-config-vault/     # Obsidian knowledge base wiki
    ├── CLAUDE.md                   # Wiki conventions (compile/query/audit)
    ├── raw/                        # Source material inbox
    ├── wiki/                       # LLM-maintained structured wiki
    │   ├── _master-index.md        # Entry point — all topics listed
    │   ├── architecture/           # Flake modules, data flows, threat model
    │   ├── compliance-frameworks/  # 10 frameworks, canonical config values
    │   ├── nixos-platform/         # NixOS compliance advantages and gotchas
    │   ├── hipaa/                  # ePHI risk, data flows, key findings
    │   ├── pci-dss/                # v4.0 requirements, scanning, anti-malware
    │   ├── ai-security/            # OWASP, MITRE ATLAS, residual risks
    │   ├── ai-governance/          # AI RMF, EU AI Act, model supply chain
    │   ├── shared-controls/        # 16 cross-framework controls, evidence, secrets
    │   └── review-findings/        # Master review results, lessons learned
    └── output/                     # Query results and reports (gitignored)
```

## How It Fits Together

**PRDs** (`docs/prd/`) define the requirements — what controls are needed, which frameworks demand them, and the resolved canonical configuration values. Start with `prd.md` for the architecture, then `MASTER-REVIEW.md` for known issues.

**Wiki** (`compliant-nix-config-vault/`) is a structured knowledge base built from the PRDs. It distills ~475KB of PRD content into cross-linked, navigable articles organized by topic. Open it in [Obsidian](https://obsidian.md) to browse the wiki graph, or read the markdown directly. Entry point: `wiki/_master-index.md`.

**Flake** (`flake.nix`, `modules/`, `hosts/ai-server/`) is a scaffolded skeleton. The six modules — `stig-baseline`, `gpu-node`, `lan-only-network`, `audit-and-aide`, `agent-sandbox`, `ai-services` — are stubs that import each other in dependency order so the flake evaluates end-to-end. Implementation is tracked in [`todos/`](todos/README.md), starting with ARCH-01 (this skeleton) and ARCH-03 (CI evaluation gate).

## Compliance Targets

| Framework | Scope |
|---|---|
| NIST SP 800-53 Rev 5 | All 20 control families (Moderate baseline) |
| HIPAA | Security Rule, Privacy Rule, Breach Notification |
| HITRUST CSF v11 | Control domains |
| PCI DSS v4.0 | All 12 requirements |
| OWASP Top 10 for LLMs | LLM + agentic AI threats |
| NIST AI RMF | Govern, Map, Measure, Manage |
| EU AI Act | High-risk AI system requirements |
| ISO 42001 | AI management system controls |
| MITRE ATLAS | Adversarial threat landscape for AI |
| STIG / DISA | NixOS hardening expectations |

## Wiki Workflow

The knowledge base follows the [Obsidian RAG pattern](https://x.com/karpathy/status/1914026357498794388) — no vector database, no embeddings, just structured markdown with indexed navigation.

| Verb | What It Does |
|---|---|
| **Clip** | Drop source material into `raw/` (via Obsidian Web Clipper or manually) |
| **Compile** | Process `raw/` into structured wiki articles with cross-links |
| **Query** | Ask questions — navigates `_master-index.md` → topic `_index.md` → articles |
| **Audit** | Review wiki for inconsistencies, broken links, gaps |

See `compliant-nix-config-vault/CLAUDE.md` for full conventions.
