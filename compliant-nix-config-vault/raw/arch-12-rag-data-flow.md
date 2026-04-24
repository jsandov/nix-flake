# ARCH-12 — RAG ingestion and retrieval flow in master PRD §6.3

Session notes from adding a new §6.3 "RAG Ingestion and Retrieval Flow" to the master PRD (`docs/prd/prd.md`). Closes MASTER-REVIEW "Master PRD must-fix #4" — RAG was missing as a first-class data-flow diagram, even though it is a fundamentally different path from direct inference.

Bead: `nf-c41`. Branch: `feat/arch-12-rag-data-flow`.

## Why RAG is a distinct flow (not a variant of §6.1)

§6.1 Inference Request Flow starts at "client sends prompt" and ends at "client receives response." Every stage happens at request time. Every control (TLS, rate limiting, prompt/response logging) guards that single request-response hop.

RAG breaks that model in two ways.

1. **Ingestion happens before any inference.** Source documents are acquired, chunked, embedded, and written to a vector store days, weeks, or months before an inference query ever sees them. None of §6.1's controls — TLS termination, per-request rate limiting, prompt logging — apply to ingestion. Ingestion has its own threat surface: poisoned sources, consent/licensing violations, PII that shouldn't have been vectorised, unversioned chunkers making retrieval results irreproducible.
2. **Retrieval composes its output into inference.** By the time §6.1 sees a prompt, it already contains retrieved chunks. The inference flow cannot enforce per-chunk provenance, cannot reason about classification-tier mixing, and cannot prevent indirect prompt injection that arrived through a retrieved document. Those controls must exist in the retrieval path itself, before composition.

Treating RAG as "§6.1 with an extra step" hides all of this. A distinct §6.3 makes the ingestion-time and retrieval-time controls visible, citeable, and auditable.

## Six-stage rationale

Each stage was chosen because it has controls that the adjacent stages cannot enforce.

1. **Source acquisition** — the only stage where source URI, consent, and licensing can be recorded. Once a document is chunked, the origin is a metadata fact, not an observable property. File-type allowlist lives here because downstream stages cannot tell an executable from a text file once it's a chunk.
2. **Chunking** — the only stage that knows the parent-document-to-chunk mapping. Chunker version stamping matters because two chunkers on the same source produce different retrieval results; reproducibility claims require the version be recorded.
3. **Embedding** — the only stage where model version is observable. Once a vector exists, you cannot tell which embedder produced it from the vector alone. Determinism flag is separate from version because some embedders are nondeterministic even at fixed version (GPU nondeterminism, library-version float drift).
4. **Index storage** — the only stage where encryption-at-rest and UID-scoped access control apply uniformly. Application-layer code sees decrypted vectors; the storage layer is where LUKS and filesystem permissions enforce confidentiality.
5. **Retrieval** — the only stage that sees the query-to-chunk mapping. Retrieval audit log lives here because no later stage has visibility into which chunks were considered but not selected, or their relevance scores. Classification-tier gating must happen before composition because once a Restricted chunk is in the prompt, the inference engine cannot un-see it.
6. **Inference composition** — the only stage where chunk provenance fields can be forwarded into inference logs. Indirect-prompt-injection mitigations (delimiter fencing, instruction stripping) belong here because retrieved content must be distinguished from user intent before the LLM sees a combined prompt.

## Cross-references made

- `docs/residual-risks.md` row 6 "RAG Data Lineage and Versioning" — landing spot for residual risks the flow does not eliminate (application-layer stamping gap).
- `docs/prd/prd-ai-governance.md` §A.6 and §3.2.1 — framework driver (ISO 42001 Annex A.6.2 data management). §3.2.1 already contains the detailed data-governance requirements; §6.3 operationalises them as a data-flow diagram.
- `modules/canonical/default.nix` `logRetention.aiDecisionLogs = "18month"` — retention target for retrieval audit logs, keeping RAG logs aligned with the rest of the AI decision log retention policy rather than inventing a new class.
- Internal PRD references: §6.1 (inference engine), §7.1 (LUKS at-rest), §7.8 (model provenance for embedder verification), §7.16 (data classification tiers for retrieval gating).

## Why aspirational, not implemented

The repository contains no RAG application code. No vector store module, no chunker, no retrieval service, no ingestion CLI. §6.3 describes the flow such code would implement.

The alternative — "omit the section until AI-20 builds something" — was rejected because:

- Residual-risks row 6 already promises "AI-20 will expand this row with the specific schema the future RAG application must emit." That promise needs an architectural home. §6.3 is it.
- The governance doc (prd-ai-governance §3.2.1) already lists detailed RAG data-governance requirements. Without a §6.3 diagram, those requirements sit in prose with no visual anchor. Reviewers skim diagrams; they skip prose.
- Future modules in adjacent work (evidence generation, classification tagging, retention policy) will cite §6.3 as their RAG integration point. Better to have a stable target than to rewrite every citation when RAG lands.

The "not currently implemented" paragraph at the end of §6.3 is the contract: the flow is design intent, AI-20 is the materialisation ticket.

## Decisions during edit

- **Existing §6.4 "RAG Pipeline Flow" was a thin earlier attempt.** 8 lines, no ingestion-time controls, no provenance, no tier gating. The new §6.3 supersedes it entirely. The earlier §6.4 was removed rather than kept, to avoid two overlapping RAG descriptions diverging over time. The old §6.3 "Audit and Evidence Flow" was renumbered to §6.4 so Audit stays in §6 but RAG takes the earlier number (matching the task spec and the natural reading order: request → agent → RAG → audit).
- No code changes. Every cross-reference in §6.3 points at a destination that already exists (verified before commit).
- Diagram is deliberately ASCII, matching §6.1 and §6.2 style; no Mermaid/PlantUML. The master PRD is read by both engineers and compliance assessors; ASCII survives every rendering path.

## Follow-ups to seed for AI-20

- Vector store selection (Qdrant, Weaviate, LanceDB) — each has different at-rest encryption and access-control stories.
- Chunk schema spec — exact fields, serialisation format, version discipline.
- Retrieval audit log schema — aligning with the broader inference log schema from AI-22 so §6.1 and §6.3 logs are joinable.
- Classification-tier propagation — how a chunk inherits its source document's tier, and how retrieval enforces the "Restricted chunks cannot land in non-Restricted contexts" rule.
