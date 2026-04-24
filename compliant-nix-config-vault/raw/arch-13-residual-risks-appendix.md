# ARCH-13 — Residual-risk appendix

Session notes from bootstrapping `docs/residual-risks.md`. Consolidates "what infrastructure cannot solve" across frameworks in one place so compliance assessors see the gaps explicitly rather than assume unstated controls.

## Why a consolidated appendix

Several framework PRDs implicitly assumed the infrastructure would handle things that it provably cannot — prompt injection detection (OWASP), calibrated confidence gating (OWASP LLM09), structured Article 12 inference logs (EU AI Act), model-provenance attestation (AI governance). MASTER-REVIEW flagged this as a systemic issue: ~60% of OWASP's listed controls require custom application code that doesn't exist.

Two bad outcomes if residual risks stay implicit:

1. Compliance assessors read the PRD, assume the control is implemented, and fail the assessment when they can't find evidence.
2. Operators deploy the system believing they have defense-in-depth against threats the infra never addressed.

The appendix makes the gaps a first-class artifact, parallel to `docs/resolved-settings.yaml`. Resolved settings answers "how did you reconcile framework conflicts?" — residual risks answers "what did you accept you couldn't solve?"

## Schema (five fields per row)

- **Risk** — one-line summary.
- **Source** — framework(s) and section(s) that name the risk.
- **Why infrastructure cannot fully mitigate** — specific technical reason.
- **What would change the answer** — the hardware/software/organisational addition that would move the risk from residual to mitigated.
- **Acceptance / mitigation strategy** — what the project currently does.

Numbered but stable: renumbering breaks cross-references from PRDs and wiki.

## Initial nine rows

Bootstrapped rows span HIPAA, OWASP, AI governance, ISO 42001, EU AI Act, HITRUST:

1. **Live-memory ePHI** — the pivotal open decision. Points at AI-04 (SEV/TDX vs signed acceptance letter).
2. **Prompt injection (LLM01)** — application-layer orchestrator needed; AI-12 will expand.
3. **Model provenance — trust-on-first-download** — no cryptographic chain back to model author; SLSA/sigstore would change answer.
4. **GPU VRAM residue** — single-tenant bounds it; AI-25 expands.
5. **ePHI IPC channels** — Unix sockets + shared memory + D-Bus; AI-24 expands.
6. **RAG data lineage** — requires app-layer stamping; AI-20 expands.
7. **EU AI Act Article 12 structured logs** — Ollama doesn't emit them; AI-22 ships the proxy.
8. **Calibrated confidence (LLM09)** — Ollama doesn't expose log probabilities; out of scope.
9. **HITRUST maturity Level >3** — takes measurement history; supported by ARCH-10 evidence generator.

## Design decisions

### Markdown, not YAML

Unlike `resolved-settings.yaml`, this appendix is prose-heavy. Each row's "why" and "what would change" fields benefit from narrative that YAML would turn into multi-line string blocks. Markdown keeps it human-reviewable.

### Landing spot, not final content

AI-12, AI-13, AI-20, AI-22, AI-24, AI-25 will each add or expand rows. ARCH-13's job is to ship the file + schema + initial bootstrap so those later TODOs have somewhere to go. Writing comprehensive rows now would overlap with those later items.

Instead, rows 2–8 have pointers in their Acceptance field: "AI-X expands this row." The later TODO's PR then edits the specific row rather than creating a new doc.

### Cross-reference from the PRD

Master PRD §8.4 ("Application-layer gaps") updated to link into `docs/residual-risks.md`. Previously the master PRD acknowledged the gap in one sentence; now the narrative continues in a dedicated doc with specific rows per risk.

No other PRD cross-references added in this PR — the framework-specific PRDs will pick up pointers when their AI-XX TODO lands and expands the relevant row.

### Stable numbering

Numbered rows with strict "never renumber" policy, same as `docs/resolved-settings.yaml`. A superseded row gets strikethrough + a new row appended. Stability matters because future docs will reference rows by number.

## Interaction with other modules

- **`modules/meta/default.nix`** (ARCH-08) — declares the threat model adversaries and out-of-scope attacks. The residual-risks appendix is the narrative companion: meta says "we accept physical-access is out of scope"; residual-risks says "here's what that acceptance means for ePHI in RAM."
- **`docs/resolved-settings.yaml`** (ARCH-04) — a cross-framework conflict-resolution log. The residual-risks appendix is its complement: resolved-settings is "here's what we decided"; residual-risks is "here's what we couldn't decide away."
- **Future `ai-services` module** — when it lands, ShouldRead from `config.system.compliance.threatModel.adversaries` and cross-reference residual-risks row numbers in its own option descriptions.

## Why this is docs-only

The file contains no executable content and ships no code. Pure prose. Doesn't trip any existing CI lint (no FHS paths, no secret patterns, no audit-rule syntax). Should land cleanly on the first CI iteration.

## Suggested wiki compile targets

- `wiki/shared-controls/residual-risks-register.md` (new) — a short wiki article pointing at `docs/residual-risks.md`, explaining the schema, and documenting the "add a row" procedure. Parallel to [[canonical-config]] in style.
- `wiki/ai-security/` — the existing articles here (residual-risks, owasp-*) should cross-reference specific rows in the new appendix so the wiki and the PRD docs agree on the canonical residual-risk list.
- Extend `wiki/review-findings/lessons-learned.md` with an entry on "admitting residual risk is a compliance strategy" — worth capturing because it's counterintuitive to first-time compliance-as-code implementers.

## Deferrals for future sessions

- **Rows 2–8 expansion** — AI-12, AI-13, AI-20, AI-22, AI-24, AI-25 each add specifics.
- **HIPAA-specific register (AI-13)** — rows 1, 5, 6 are particularly HIPAA-relevant; AI-13 will add a HIPAA-indexed view alongside the framework-agnostic view.
- **OWASP-specific residual section (AI-12)** — rows 2, 4, 8 are particularly OWASP-relevant; AI-12 expands with OWASP-LLM-numbered entries.
- **ATLAS technique cross-references (AI-21)** — each row that maps to a MITRE ATLAS technique gets the ID added when AI-21 lands.
