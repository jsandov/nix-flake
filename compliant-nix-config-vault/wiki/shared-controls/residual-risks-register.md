# Residual Risks Register

Pointer to `docs/residual-risks.md` — the project's consolidated "what infrastructure cannot solve" appendix. Complements [[canonical-config|resolved-settings.yaml]] as one of the two first-class compliance narrative artifacts.

## The Two Narratives

| Artifact | Answers | Format |
|---|---|---|
| `docs/resolved-settings.yaml` | How did we reconcile framework conflicts? | YAML rows with rejected-values metadata |
| `docs/residual-risks.md` | What did we accept we couldn't solve? | Markdown sections with five-field schema |

Admitting residual risk is a deliberate compliance strategy. False confidence from implicit gaps produces worse audit outcomes than explicit acknowledgment — a MASTER-REVIEW finding that affected several framework PRDs.

## Schema

Each row in `docs/residual-risks.md`:

- **Risk** — one-line summary.
- **Source** — framework(s) and section(s) that name the risk.
- **Why infrastructure cannot fully mitigate** — specific technical reason.
- **What would change the answer** — hardware/software/organisational addition that would move the risk from residual to mitigated.
- **Acceptance / mitigation strategy** — what the project currently does.

## Stable Numbering

Rows are numbered sequentially and **never renumbered**. Cross-references from PRDs, wiki, and raw notes use the row number. A superseded row gets a strikethrough heading (`~~## N. Title~~`) and a new row is appended.

## Current Rows (9 as of the ARCH-13 bootstrap)

Each row listed here with the TODO that expands it — most rows ship in their bootstrap form and wait for framework-specific TODOs to add detail.

| # | Risk | Expanded by |
|---|---|---|
| 1 | Live-memory ePHI | AI-04 (human decision) |
| 2 | Prompt injection LLM01 | AI-12 |
| 3 | Model provenance — trust-on-first-download | (stable) |
| 4 | GPU VRAM residue | AI-25 |
| 5 | ePHI IPC channels | AI-24 |
| 6 | RAG data lineage | AI-20 |
| 7 | EU AI Act Article 12 structured logs | AI-22 |
| 8 | Calibrated confidence LLM09 | (out of scope) |
| 9 | HITRUST maturity Level >3 | (evidence accumulation) |

## Adding a Row

1. Identify the framework / section that raises the risk.
2. Write a one-line summary under the next numbered heading in `docs/residual-risks.md`.
3. Fill in the five-field schema.
4. If the row is tied to a future TODO, link the TODO ID in the Acceptance field.
5. Update the relevant framework PRD to point at the appendix rather than restating inline.

## Why This Is In `shared-controls/`

Residual risks span every framework. The register itself is a shared artifact — HIPAA residual rows, OWASP residual rows, HITRUST residual rows all live in the same numbered list. Framework-specific PRDs cross-reference back rather than maintain parallel copies.

## Relation to Meta Module

[[../architecture/meta-module]] declares the threat model, data classification, and tenancy. `residual-risks.md` documents the consequences — what the infrastructure cannot protect *given* those declarations. The two are read together: meta says "physical access is out of scope"; residual-risks row 1 explains what that acceptance means for ePHI in RAM.

## Key Takeaways

- Residual-risks register is the project's "what we cannot solve" narrative, complementing resolved-settings' "how we resolved conflicts."
- Nine bootstrap rows; six expand via AI-side P1/P2 TODOs.
- Five-field schema per row; stable numbering; append-only with strikethrough supersession.
- Admitting residual risk is a deliberate strategy — false confidence produces worse audit outcomes.
- Pairs with [[../architecture/meta-module|meta]] as the "declaration vs consequences" narrative.
