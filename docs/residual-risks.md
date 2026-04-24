# Residual Risks

Risks that the infrastructure of this project does not and cannot eliminate. Documented here so compliance assessors see the gaps explicitly rather than assume unstated controls. Each row identifies the source framework, why infrastructure alone cannot fully mitigate it, what would change the answer, and the documented acceptance or mitigation strategy.

The existence of this file is a deliberate compliance decision: admitting residual risk is preferable to the false confidence that the MASTER-REVIEW flagged as a systemic issue across several framework PRDs (notably OWASP, where ~60% of listed controls require custom application code that does not exist).

## Schema

Each section below uses this shape:

- **Risk** — one-line summary.
- **Source** — framework(s) and section(s) that name the risk.
- **Why infrastructure cannot fully mitigate** — the specific technical reason the NixOS flake alone is insufficient.
- **What would change the answer** — the hardware, software, or organisational addition that would move the risk from residual to mitigated.
- **Acceptance / mitigation strategy** — what the project currently does about it.

This appendix is the landing spot for AI-12 (OWASP residual-risk expansion), AI-13 (HIPAA residual-risk register), AI-20 (RAG data governance gaps), and future residual-risk registrations. Each of those later TODOs adds rows here rather than restating the risk in its own framework doc.

---

## 1. Live-memory ePHI

**Risk.** Electronic protected health information is present in host RAM and GPU VRAM during inference. Both are readable by a privileged kernel-side attacker, and GPU VRAM is not covered by standard Linux memory-protection mechanisms.

**Source.** HIPAA §164.312(a)(1) — Security Rule access controls. MASTER-REVIEW "HIPAA must-fix #1." [[../compliant-nix-config-vault/wiki/hipaa/|HIPAA deep-dive]].

**Why infrastructure cannot fully mitigate.** NixOS has no mechanism to encrypt RAM or VRAM against a root-privileged attacker. Standard systemd hardening (`ProtectSystem=strict`, `MemoryDenyWriteExecute` on non-CUDA services) reduces the *attack surface* for reaching RAM but does not make the memory itself confidential. GPU VRAM sits even further outside OS-level isolation — cgroups cannot limit it, memory-protection directives do not apply, and consumer NVIDIA drivers do not support any form of encrypted memory.

**What would change the answer.** AMD SEV-SNP or Intel TDX hardware would provide confidential memory for CPU-side ePHI. NVIDIA Confidential Computing (H100+, datacenter-only) would provide the equivalent for GPU VRAM. Any of these is a hardware-tier decision, not a software change — they require specific CPU and GPU SKUs.

**Acceptance / mitigation strategy.** Unresolved pending AI-04 decision. Two paths:
- If SEV/TDX hardware is provisioned: the risk is cryptographically mitigated.
- If consumer hardware (workstation + consumer NVIDIA) is used: the deployment ships with a signed risk-acceptance letter covering HIPAA §164.308(a)(1)(ii)(B), HITRUST privacy domain, and EU AI Act high-risk classification. Core dumps are disabled (canonical `nixosOptions.coredumpStorage = "none"`) to prevent RAM contents reaching disk on crash, partially reducing the attack window.

---

## 2. Prompt Injection (OWASP LLM01)

**Risk.** User-supplied prompts can override system instructions, extract private training data, or manipulate the model into performing actions the operator did not sanction.

**Source.** OWASP Top 10 for LLM Applications — LLM01 Prompt Injection. MASTER-REVIEW "OWASP must-fix #4."

**Why infrastructure cannot fully mitigate.** Prompt injection is a semantic attack at the application layer. Systemd hardening, filesystem permissions, and network ACLs cannot distinguish a legitimate user query from a prompt-injection payload — both look like plain text arriving at the Ollama API. Detection requires content-aware filtering that understands model context.

**What would change the answer.** An application-layer orchestrator running in front of Ollama that implements: input sanitisation for known-bad prompt patterns, output filtering for leaked system-prompt content, structured prompt templates that isolate user input from instructions, and content-safety classifiers on outputs. None of these are in this project's current scope.

**Acceptance / mitigation strategy.** Monitoring-only at the infrastructure layer — prompt and completion bodies are logged via systemd journal so post-hoc review can identify attacks, but nothing is blocked at runtime. The OWASP residual-risk section (AI-12) will expand this row with specific mitigations the application-layer orchestrator is expected to implement when it exists.

---

## 3. Model Provenance — Trust-on-First-Download

**Risk.** Ollama's model distribution has no cryptographic chain of trust back to the model author. A compromised registry or CDN could serve a tampered model, and the first download would be accepted as the baseline.

**Source.** AI governance / ATLAS T1586 (Supply Chain Compromise), MASTER-REVIEW "AI Gov must-fix #1."

**Why infrastructure cannot fully mitigate.** No cryptographic signature attestation exists in the Ollama ecosystem. SHA-256 hash comparison against a manually-recorded baseline detects *subsequent* tampering but cannot detect compromise at the moment of first acquisition.

**What would change the answer.** Upstream adoption of SLSA provenance, sigstore-style signing, or GPG-signed model manifests by model providers. Would require changes in the Ollama registry protocol and in model-author workflows — both outside this project's control.

**Acceptance / mitigation strategy.** The `ai-model-fetch` script (see `docs/prd/prd-ai-governance.md`) enforces hash verification against a locally-maintained manifest. Operators should acquire hashes out-of-band from model providers' official documentation when available, and fetch from multiple network vantage points to catch CDN-level tampering. The provenance log records the acquisition source so an audit trail exists even though the trust is first-download-established.

---

## 4. GPU VRAM Residue

**Risk.** GPU VRAM is not zeroed between inference runs. A model that handled Restricted data leaves weight-derived or activation-derived content in VRAM; a subsequent process with GPU access can read that content.

**Source.** MASTER-REVIEW "OWASP must-fix #3." Same line of reasoning as live-memory ePHI (risk #1), but specifically about the GPU.

**Why infrastructure cannot fully mitigate.** Linux cgroups control host RAM, not GPU VRAM. `DeviceAllow` controls which processes can access the GPU at all, but a process that legitimately has access reads residue from the previous tenant. No NVIDIA driver API exposes "zero VRAM on context teardown" for consumer cards.

**What would change the answer.** NVIDIA Confidential Computing (H100+) provides per-tenant VRAM isolation. For non-CC hardware, a custom process that explicitly writes zeros to allocated VRAM before releasing it would mitigate between same-process-owner runs — not trivial and not universal.

**Acceptance / mitigation strategy.** Single-tenant declaration (`config.system.compliance.tenancy.mode = "single-tenant"`) removes the multi-tenant angle: if all VRAM is used by the same tenant, residue does not cross tenancy boundaries. Ollama is gated behind the `agent-sandbox` UID scheme and a reverse-proxy-only network exposure so GPU access is scoped to the single Ollama service. Residual risk for a compromised Ollama process still reading across sessions is documented but not further mitigated. AI-25 expands this row.

---

## 5. ePHI IPC Channels (Unix Sockets, Shared Memory, D-Bus)

**Risk.** Unix-domain sockets and shared-memory segments between services can carry ePHI without the same audit coverage that TCP/TLS channels receive. D-Bus messaging similarly.

**Source.** HIPAA §164.312(e)(1). MASTER-REVIEW "HIPAA should-fix #6."

**Why infrastructure cannot fully mitigate.** Systemd's `IPAddressAllow`/`IPAddressDeny` apply to network sockets, not Unix sockets or shared memory. `RestrictAddressFamilies` can deny `AF_UNIX` entirely, but many legitimate services need it (journald, logind, etc.). Shared memory has no comparable access-control primitive beyond filesystem permissions on `/dev/shm`.

**What would change the answer.** An application-layer IPC protocol that encrypts payloads in transit even over loopback, with payload audit logging. None of the current Ollama / application wiring does this.

**Acceptance / mitigation strategy.** Agent-sandbox module (AI-08, future) will use `PrivateTmp=true` (canonical) to isolate per-service `/tmp` and `/dev/shm`. UIDs are per-service (AI-08 scope) so cross-service Unix-socket access is filesystem-perm-gated. AI-24 expands this row with specific socket and shm hardening.

---

## 6. RAG Data Lineage and Versioning

**Risk.** Retrieval-augmented generation ingests text from arbitrary sources into a vector store; the provenance chain from original document → chunk → embedding → retrieval → response is not captured by infrastructure.

**Source.** ISO 42001 A.6.2 (data governance), EU AI Act Article 12 (logging). MASTER-REVIEW "AI Gov must-fix #4."

**Why infrastructure cannot fully mitigate.** The RAG pipeline is application code. NixOS can host the vector store and wrap it in a systemd unit, but it does not know what is being stored. Per-chunk provenance requires the application to record it at ingestion time.

**What would change the answer.** A RAG application that stamps every chunk with: source URI, acquisition timestamp, content hash, chunker version, embedding model version, consent/licensing metadata. Retrieved chunks propagate these fields into the inference log.

**Acceptance / mitigation strategy.** Out of current scope. AI-20 will expand this row with the specific schema the future RAG application must emit. Until then, RAG use is documented as "no lineage controls; not suitable for Restricted data."

---

## 7. EU AI Act Article 12 Structured Inference Logs

**Risk.** EU AI Act Article 12 requires structured per-request inference logs (input, output, model version, confidence, decision) retained for a specified period. Ollama's native logging does not produce these structured records.

**Source.** EU AI Act Article 12. MASTER-REVIEW "AI Gov should-fix #3."

**Why infrastructure cannot fully mitigate.** Ollama writes text logs to systemd journal. Parsing those back into structured records is error-prone and loses fields that Ollama does not emit (confidence scores, structured decision metadata).

**What would change the answer.** Either an upstream Ollama feature adding structured logging, or an application-layer proxy that intercepts every inference request and writes a structured record. AI-22 will ship the proxy when the application layer exists.

**Acceptance / mitigation strategy.** Retention target of 18 months is declared in canonical (`canonical.logRetention.aiDecisionLogs = "18month"`). Emission depends on AI-22 (the Article 12 logger). Until then, Article 12 compliance is aspirational, not enforced.

---

## 8. Calibrated Confidence for LLM09 (Misinformation)

**Risk.** OWASP LLM09 (Misinformation) expects confidence-gated responses — models refusing to answer when uncertain. Ollama does not expose calibrated log probabilities that would enable this gating.

**Source.** OWASP LLM09. MASTER-REVIEW "OWASP should-fix #1."

**Why infrastructure cannot fully mitigate.** Confidence gating is a model-output interpretation problem. Infrastructure cannot synthesise confidence scores; it can only pass them through if they exist.

**What would change the answer.** An upstream Ollama feature exposing token-level log probabilities in the API response, plus an application-layer gate that computes a response-level confidence metric and refuses responses below a threshold.

**Acceptance / mitigation strategy.** Out of scope. Documented as not mitigated.

---

## 9. HITRUST Maturity Level Claims Beyond 3

**Risk.** HITRUST CSF assessors expect Year-1 controls to demonstrate Level 2–3 maturity (implemented + documented). Claiming Level 4 (measured) or Level 5 (managed) in a first-year assessment produces immediate pushback.

**Source.** HITRUST CSF v11 scoring guidance. MASTER-REVIEW "HITRUST must-fix #2."

**Why infrastructure cannot fully mitigate.** Maturity levels above 3 require measurement history and continuous-improvement evidence, which take time to accumulate regardless of how well the controls are implemented technically.

**What would change the answer.** 12–24 months of measured compliance evidence + continuous-improvement process evidence — an organisational investment, not a technical one.

**Acceptance / mitigation strategy.** All HITRUST-targeted controls are scoped at Level 3 maximum for Year 1 per AI-15. Infrastructure supports the evidence collection (ARCH-10 evidence generator) that will enable Level 4 claims in Year 2.

---

## Adding a new row

1. Identify the framework / section that raises the risk.
2. Write a one-line summary under a numbered heading.
3. Fill in the five fields: Source, Why, What-would-change, Acceptance.
4. If the row is tied to a future TODO (e.g., AI-12 will expand it), link the TODO ID in the Acceptance field.
5. Update the relevant framework PRD to point at this appendix rather than restating the residual-risk content inline.

Rows are numbered but the numbers are stable — do not renumber. A superseded row is marked `~~## N. Title~~` and a new row is appended.
