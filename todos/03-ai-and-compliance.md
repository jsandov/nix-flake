# TODO — AI Security, Governance & Healthcare Compliance

This slice covers the three AI-specific modules (`gpu-node`, `agent-sandbox`, `ai-services`) and the regulated-data frameworks (HIPAA, HITRUST, OWASP LLM + Agentic, AI governance). It depends heavily on **upstream primitives that the flake does not own**: Ollama's content-addressed blob format, the CUDA JIT's hard requirement for W+X memory (which collides with `MemoryDenyWriteExecute`), Ollama's lack of `sd_notify` (which breaks `WatchdogSec`), and Ollama's unstructured service logs (which block EU AI Act Article 12 structured per-request logging without app-layer help). Because of those ceilings, every control in this list must be explicitly tagged **enforced** (kernel/systemd/Nix guarantees it at rebuild time) or **aspirational** (requires custom application code on port 8000, a policy document, or a hardware platform we may not have). The `MASTER-REVIEW.md` finding that ~60% of OWASP controls require app code that doesn't exist is the central honesty problem these TODOs are built around — the flake must stop pretending otherwise, starting with a Residual Risk section in every AI-facing module and an accepted-risk disposition for live-memory ePHI before the first `nixos-rebuild switch` ever runs against patient data.

---

## P0 — Blocks evaluation, breaks inference, or leaves regulated data indefensible

### AI-01: Scope MemoryDenyWriteExecute to non-CUDA services only
- **Priority:** P0
- **Effort:** S
- **Depends on:** none
- **Source:** MASTER-REVIEW.md "Systemic Issue #2" (CUDA W+X), prd-hipaa.md §164.312(a)(1), wiki/ai-security/ai-security-residual-risks.md §6

Split the systemd hardening attrset in `ai-services` so `MemoryDenyWriteExecute=true` is applied to `agent-runner`, `ai-api`, approval-gate, and monitoring units, and **explicitly set `false`** on `ollama.service` and any CUDA-touching unit. Add an assertion in the module that fails evaluation if a unit declaring `environment.CUDA_*` or `DeviceAllow=/dev/nvidia*` also has `MemoryDenyWriteExecute=true`, with a comment pointing at the NVRTC JIT requirement.

### AI-02: Remove WatchdogSec from Ollama, replace with external health timer
- **Priority:** P0
- **Effort:** S
- **Depends on:** none
- **Source:** MASTER-REVIEW.md AI Gov "Must fix #2", wiki/ai-governance/ai-governance-overview.md (MEASURE)

Delete `WatchdogSec=300` (and any `Type=notify`) from `ollama.service`. Ollama does not implement `sd_notify`, so the watchdog only produces spurious SIGABRT kills. Replace with a separate `ai-services-healthcheck.timer` running every 60s that curls `/api/tags` and only restarts Ollama after 3 consecutive failures. Document the rationale inline.

### AI-03: Fix ai-model-fetch / integrity script for Ollama blob format
- **Priority:** P0
- **Effort:** M
- **Depends on:** none
- **Source:** MASTER-REVIEW.md AI Gov "Must fix #1", wiki/ai-governance/model-supply-chain.md "Ollama Storage Format"

Rewrite the model-fetch, hash-verify, and AIDE-register helpers to walk `/var/lib/ollama/models/manifests/` JSON, resolve the layer whose `mediaType` contains `"model"`, and hash the corresponding blob at `/var/lib/ollama/models/blobs/sha256-<hex>`. Remove every `find … -name "*.bin"` glob. Emit a failing exit code (not a warning) if the manifest-declared digest does not match the blob filename.

### AI-04: Disposition the live-memory ePHI risk (SEV/TDX vs accepted risk)
- **Priority:** P0
- **Effort:** M
- **Depends on:** none
- **Source:** prd-hipaa.md §164.312(e) + §164.308(a)(1)(ii)(B), wiki/hipaa/live-memory-ephi-risk.md, MASTER-REVIEW.md HIPAA "Must fix #1"

Produce a written disposition — checked in at `docs/policies/risk-acceptance-live-memory-ephi.md` — that either (a) mandates AMD SEV-SNP or Intel TDX hardware with the flake refusing to enable `ai-services` on non-confidential-computing hosts, or (b) formally accepts the risk and enumerates the compensating controls from AI-05/AI-06/AI-07 plus physical-access restrictions. This decision gates every other HIPAA TODO and must be signed before any ePHI touches the box. Flag to the human: this is the single biggest architectural call in the suite.

### AI-05: Disable core dumps system-wide to prevent ePHI on disk
- **Priority:** P0
- **Effort:** S
- **Depends on:** AI-04
- **Source:** wiki/hipaa/live-memory-ephi-risk.md "Software/Operational Mitigations", MASTER-REVIEW.md HIPAA "Should fix"

Add to the shared hardening module: `systemd.coredump.extraConfig = "Storage=none\nProcessSizeMax=0";`, `boot.kernel.sysctl."kernel.core_pattern" = "|/bin/false";`, `security.pam.loginLimits` entries setting `core` hard/soft to 0, and `systemd.services.<each-ai-unit>.serviceConfig.LimitCORE = 0`. A segfaulting inference dumping VRAM contents to `/var/lib/systemd/coredump` is an immediate §164.402 breach; the control must be belt-and-suspenders.

### AI-06: Lock OLLAMA_HOST to loopback and harden ai-services network exposure
- **Priority:** P0
- **Effort:** S
- **Depends on:** none
- **Source:** MASTER-REVIEW.md "Systemic Issue #2" (OLLAMA_HOST), prd-owasp.md LLM01, prd-stig-disa.md

Set `OLLAMA_HOST=127.0.0.1:11434` (not `0.0.0.0`) and `OLLAMA_ORIGINS=""`. Force all external access through the authenticated `ai-api` proxy on port 8000. Add `IPAddressDeny=any` + `IPAddressAllow=127.0.0.1/32` on `ollama.service`, and a NixOS assertion that fails eval if any module tries to set `OLLAMA_HOST` to a non-loopback address. Ollama has no auth; exposing it directly is a §164.312(a)(1) + LLM01 violation.

### AI-07: Add OLLAMA_NOPRUNE correction and remove security framing
- **Priority:** P0
- **Effort:** XS
- **Depends on:** none
- **Source:** MASTER-REVIEW.md HIPAA "Should fix", wiki/hipaa/hipaa-key-findings.md

Delete all comments/PRD text that describe `OLLAMA_NOPRUNE=1` as a security control. It is a storage-management flag and claiming otherwise pollutes the evidence package. Replace with a neutral comment: "storage retention flag; see model retirement procedure for deletion policy."

---

## P1 — Core module correctness, must-ship honesty sections, framework taxonomy

### AI-08: Implement agent-sandbox module with UID-per-agent allocation
- **Priority:** P1
- **Effort:** L
- **Depends on:** ARCH-01 (canonical config), AI-01
- **Source:** prd-owasp.md AGT-04/AGT-07, wiki/ai-security/owasp-agentic-threats.md, prd.md Phase 2

Build `modules/agent-sandbox.nix` that takes an attrset of agent names and produces one systemd unit per agent with: dedicated system user/group (`users.users.agent-<name>`), `DynamicUser=false` (we want stable UIDs for audit), `PrivateTmp=true`, `ProtectSystem=strict`, `ProtectHome=true`, `ProtectKernelTunables/Modules/Logs=true`, `ProtectClock=true`, `PrivateDevices=true`, `DeviceAllow=[]`, `CapabilityBoundingSet=""`, `NoNewPrivileges=true`, `SystemCallFilter=@system-service`, `SystemCallArchitectures=native`, `RestrictAddressFamilies=AF_UNIX AF_INET`, `ReadOnlyPaths=/run/agent-goals`, `NoExecPaths=/var/lib/agent-runner/workspace`, `LimitFSIZE=100M`, `RuntimeMaxSec=1800`, `MemoryMax` and `CPUQuota` from canonical config. Separate Unix socket per agent with `SO_PEERCRED` verification in the proxy.

### AI-09: Implement ai-services module with Ollama + API proxy split
- **Priority:** P1
- **Effort:** L
- **Depends on:** AI-01, AI-02, AI-06, ARCH-01
- **Source:** prd.md Phase 2b, prd-owasp.md LLM01/LLM10, prd-ai-governance.md Article 12

Build `modules/ai-services.nix` containing: (a) `ollama.service` bound to loopback only, run as dedicated `ollama` user, `ReadWritePaths=/var/lib/ollama`, `MemoryDenyWriteExecute=false`, no watchdog; (b) `ai-api.service` on port 8000 running as `ai-services` user, full systemd hardening including MDWE=true, TLS terminator, rate limits (30 req/min/client) via NixOS option, structured per-request logging to syslog facility `local6` for Article 12; (c) model registry read-only bind-mount at `/etc/ai/model-registry.json`. Add assertion that `ai-api` must run before `ollama` is reachable.

### AI-10: Implement gpu-node module with VRAM-limit blind-spot documentation
- **Priority:** P1
- **Effort:** M
- **Depends on:** ARCH-01
- **Source:** prd.md Phase 2a, wiki/ai-security/ai-security-residual-risks.md §4, MASTER-REVIEW.md OWASP "Must fix #3"

Build `modules/gpu-node.nix` that enables `hardware.nvidia`, pins driver version via `config.boot.kernelPackages.nvidiaPackages.<channel>`, installs CUDA runtime via overlay, adds `nvidia-smi`-based `gpu-metrics.timer` firing every 60s and alerting at 80% / 95% VRAM. Include a prominent comment block stating that cgroups cannot enforce VRAM; enforcement is via (1) model-registry size allowlist, (2) single-concurrent-inference serialization in `ai-api`, (3) monitoring alerts. Add `services.xserver.enable = false` + explicitly set videoDrivers only if xserver ever gets enabled elsewhere.

### AI-11: Move approval gate inside the Nix-managed boundary
- **Priority:** P1
- **Effort:** M
- **Depends on:** AI-08
- **Source:** MASTER-REVIEW.md AI Gov "Must fix #3", wiki/ai-security/owasp-agentic-threats.md AGT-08

Relocate the approval-gate server from `/opt/ai/approval-gate-server.py` to a packaged Nix derivation (`pkgs.approval-gate` built from `pkgs/approval-gate/`), with its systemd unit, read-only config path, and socket all declared in `modules/agent-sandbox.nix`. `/opt/` is outside the reproducible boundary and breaks rollback. The unit should be `After=agent-*.service`, use a separate UID, and expose a Unix socket rather than TCP.

### AI-12: Add "Residual Risk and Known Limitations" section to OWASP PRD
- **Priority:** P1
- **Effort:** M
- **Depends on:** none
- **Source:** MASTER-REVIEW.md OWASP "Must fix #1 + #2", wiki/ai-security/ai-security-residual-risks.md

Append a dedicated section to `docs/prd/prd-owasp.md` that (a) states explicitly "~60% of listed controls require custom application code that does not yet exist," (b) tags every LLM01–LLM10 and AGT-01–AGT-09 control as **ENFORCED** (Nix/systemd/kernel) or **ASPIRATIONAL** (app-layer/policy), (c) enumerates the seven items from the residual-risks wiki page (prompt injection, app-layer gap, goal hijacking invisibility, VRAM cgroup gap, TOFU provenance, CUDA+MDWE collision, live-memory ePHI, confidence-score unreliability), and (d) states bluntly that infrastructure logs cannot detect prompt injection.

### AI-13: Add Residual Risk + accepted-risk register to HIPAA PRD
- **Priority:** P1
- **Effort:** M
- **Depends on:** AI-04
- **Source:** MASTER-REVIEW.md HIPAA "Must fix #1", prd-hipaa.md §164.308(a)(1)(ii)(B)

Insert a "Residual Risk & Risk Analysis" section in `docs/prd/prd-hipaa.md` covering: live-memory ePHI (RAM + VRAM), Nix-store world-readability leakage, IPC channel ePHI (stage 7 of ePHI data flow), core-dump disposition, context-window persistence between patients. Each residual risk links to the AI-04 disposition document and lists compensating controls with owners. This is the §164.308(a)(1)(ii)(B) risk analysis artifact.

### AI-14: Fix HITRUST domain taxonomy to CSF v11's 19 domains
- **Priority:** P1
- **Effort:** L
- **Depends on:** none
- **Source:** MASTER-REVIEW.md HITRUST "Must fix #1", prd-hitrust.md §domain coverage

Rewrite `docs/prd/prd-hitrust.md` to use the actual CSF v11 domain taxonomy (Domains 00–18, 19 total) from MyCSF rather than the legacy 14-domain rollup. Remap every existing control statement to its correct v11 domain. Add placeholder MyCSF requirement statement IDs (format `NNNNNvN`) with a clear TODO that they must be populated from the MyCSF portal during scoping. This is a documentation refactor, not a Nix change, but it is prerequisite to any HITRUST engagement.

### AI-15: Drop unrealistic HITRUST Level 5 maturity claims
- **Priority:** P1
- **Effort:** S
- **Depends on:** AI-14
- **Source:** MASTER-REVIEW.md HITRUST "Must fix #2"

Scrub every Level 4/5 maturity claim from the HITRUST PRD and cap Year-1 targets at Level 3 (Implemented/Measured where evidence truly exists). Level 5 (Managed-and-measured across a sustained period with demonstrated continuous improvement) is not credible on day one and will draw QA scrutiny that jeopardizes the whole assessment. Add a maturity roadmap showing Level 4 as a Year-2 goal for a narrow domain subset.

### AI-16: Add missing HITRUST domains (physical, incident mgmt, BCP, privacy)
- **Priority:** P1
- **Effort:** L
- **Depends on:** AI-14
- **Source:** MASTER-REVIEW.md HITRUST "Must fix #5", prd-hitrust.md §missing domains

Write control narratives for the domains currently missing or inadequate: physical & environmental security (single-server colocation / home-office controls), incident management (links to AI-incident types from AI governance), business continuity & disaster recovery (flake rollback + BorgBackup restore drill), and privacy practices (links to AI-17 §164.524/526/528). Each domain must name the NixOS module or policy doc that provides evidence.

### AI-17: Write §164.316 policies + Privacy Rule individual-rights procedures
- **Priority:** P1
- **Effort:** L
- **Depends on:** none
- **Source:** MASTER-REVIEW.md HIPAA "Must fix #4 + #5", wiki/hipaa/hipaa-key-findings.md, prd-hipaa.md §164.524/526/528

Create `docs/policies/` with: `security-policy.md`, `workforce-access.md`, `incident-response.md`, `sanction-policy.md`, `documentation-retention.md` (6-year Git-based retention, no force-push rule), `right-of-access-sop.md` (§164.524 query tooling against structured inference logs), `amendment-sop.md` (§164.526 RAG-store correction procedure), `accounting-of-disclosures-sop.md` (§164.528, 6-year log). Each SOP must name the NixOS user/role and log source it relies on.

### AI-18: Enable rsyslog TLS (RELP) for ePHI log transport
- **Priority:** P1
- **Effort:** M
- **Depends on:** INFRA-XX (secrets mgmt module)
- **Source:** MASTER-REVIEW.md HIPAA "Should fix" (rsyslog cleartext), prd-hipaa.md §164.312(e)(1)

Replace plain TCP rsyslog forwarding with RELP over TLS: `services.rsyslogd` config with `$DefaultNetstreamDriver gtls`, CA/cert/key paths sourced via sops-nix/agenix, `$ActionSendStreamDriverMode 1`, `$ActionSendStreamDriverAuthMode x509/name`. Cleartext log transport violates §164.312(e)(1) because logs routinely contain ePHI fragments in error messages. Refuse to evaluate the module if TLS paths are unset.

### AI-19: Fix AIDE alerting unit so $SERVICE_RESULT is actually available
- **Priority:** P1
- **Effort:** S
- **Depends on:** none
- **Source:** MASTER-REVIEW.md HIPAA "Must fix #2"

Move the AIDE failure notification into the same unit as the check (via `ExecStopPost=` or `OnFailure=` with a template that receives `%i`), not a separately-triggered unit where `$SERVICE_RESULT` is empty. Test by deliberately corrupting a monitored file and confirming the notification fires with the correct service name and result.

---

## P2 — Governance depth, adjacent frameworks, evidence quality

### AI-20: Add RAG data governance: lineage, versioning, retention (ISO 42001 A.6.2)
- **Priority:** P2
- **Effort:** L
- **Depends on:** AI-09
- **Source:** MASTER-REVIEW.md AI Gov "Should fix" (A.6.2 thin), wiki/ai-governance/ai-governance-overview.md §ISO 42001

Extend `ai-services` with a RAG corpus manager that records, per document: source URI, ingestion timestamp, ingesting-user, content hash, embedding model identity + version, corpus version. Store metadata in a git-tracked `/etc/ai/rag-manifest.json` and require a `corpus_version` bump + Nix rebuild for ingestion/removal. Add a timer that computes retrieval-precision-at-k=5 against a fixtures set and alerts below 80%. Enforce "removed-from-source ⇒ removed-from-corpus" by reconciling weekly.

### AI-21: Verify ATLAS technique IDs and lock a quarterly refresh cadence
- **Priority:** P2
- **Effort:** M
- **Depends on:** none
- **Source:** MASTER-REVIEW.md AI Gov "Should fix" (ATLAS staleness), wiki/ai-security/mitre-atlas.md

Audit every ATLAS technique ID referenced in the PRDs and wiki (T0010, T0015, T0018, T0024, T0040, T0043, T0051, T0056) against the current release at https://atlas.mitre.org and correct descriptions/mitigations. Add a scheduled review TODO to `docs/reviews/quarterly.md` requiring re-verification each quarter. Note in the PRD that ATLAS IDs are reorganized across releases and must not be treated as stable identifiers.

### AI-22: Build EU AI Act Article 12 structured inference logger in ai-api
- **Priority:** P2
- **Effort:** L
- **Depends on:** AI-09
- **Source:** MASTER-REVIEW.md AI Gov "Should fix" (Article 12), wiki/ai-governance/ai-governance-overview.md §EU AI Act

Specify and stub the `ai-api` middleware that emits one structured record per inference request containing: request ID, timestamp (UTC), principal UID, model name + registry hash, prompt hash (not plaintext — ePHI), completion hash, token counts, tool calls invoked, latency, outcome. Write as JSON lines to a dedicated append-only log forwarded via AI-18. Document explicitly that Ollama's service logs alone do NOT satisfy Article 12; the app-layer logger is the compliance artifact.

### AI-23: Add model-registry schema, approval workflow, 6-month review enforcement
- **Priority:** P2
- **Effort:** M
- **Depends on:** AI-03
- **Source:** wiki/ai-governance/model-supply-chain.md "Model Manifest Required Fields", prd-ai-governance.md

Define `/etc/ai/model-registry.json` schema (JSON Schema file in flake) with all 10 required fields, validate at eval time via a Nix assertion, and add a `model-review.timer` that fails (and alerts) on any model whose `review_due` is past. Emit a clear error stating we cannot offer cryptographic provenance — only trust-on-first-download + AIDE — so the registry is the accountability record. Add `risk_tier=high` entries requiring a signed approval file before deployment.

### AI-24: Harden ePHI IPC channels (Unix sockets, shared memory, D-Bus)
- **Priority:** P2
- **Effort:** M
- **Depends on:** AI-08, AI-09
- **Source:** wiki/hipaa/ephi-data-flow.md Stage 7, prd-hipaa.md §164.312(a)(1)

Enumerate every IPC surface carrying ePHI (Unix socket `ai-api`↔`ollama`, CUDA shared memory host↔GPU, any D-Bus usage) and enforce: socket files at `0660` with explicit group ACL, `PrivateTmp=true` on all AI services, `RestrictNamespaces=true`, D-Bus policy denying send/receive for AI services unless explicitly whitelisted. Document in the HIPAA module as stage-7 controls.

### AI-25: Document GPU VRAM residue and post-inference clearing strategy
- **Priority:** P2
- **Effort:** M
- **Depends on:** AI-10
- **Source:** wiki/ai-security/ai-security-residual-risks.md §4, MASTER-REVIEW.md PCI DSS "Should fix" (VRAM CHD residue)

Add to `gpu-node` a session-teardown hook that calls `cudaDeviceReset()` (or equivalent) between distinct principals / patient contexts where practical, plus documentation explaining which residues cannot be cleared without driver/firmware support. This is a partial mitigation — the PRD must state plainly that VRAM scrubbing on consumer NVIDIA is best-effort. Also forbids GPU sharing across agent UIDs simultaneously.

---

## P3 — Operational polish, rollout ergonomics, review hygiene

### AI-26: Ship tiered AI governance implementation guide in the repo
- **Priority:** P3
- **Effort:** M
- **Depends on:** AI-17
- **Source:** MASTER-REVIEW.md AI Gov "Must fix #4", wiki/ai-governance/tiered-implementation.md

Add `docs/governance/tiers.md` describing the three tiers (5 / 11 / 17 AI-ORG processes), the decision tree, and Nix flake outputs per tier (e.g., `ai-server-tier1`, `ai-server-tier2`, `ai-server-tier3`) that toggle which organizational evidence-gen timers and policy-doc requirements are active. A single operator should not be blocked by Tier-3 ceremony when deploying a Tier-1 personal box. ePHI automatically escalates to Tier 3.

### AI-27: Establish quarterly review cadence for ATLAS, Ollama internals, frameworks
- **Priority:** P3
- **Effort:** S
- **Depends on:** AI-21
- **Source:** MASTER-REVIEW.md "Ongoing #13", wiki/ai-security/mitre-atlas.md §Important Note

Create `docs/reviews/quarterly.md` checklist: ATLAS ID drift, Ollama blob-format changes, CUDA driver version pin, CSF v11 revision status, EU AI Act secondary-legislation releases, NIST AI RMF profile updates. Add a calendar timer (or beads reminder) with the review owner named. Each review cycle produces a dated delta doc in `docs/reviews/YYYY-Qn.md`.

### AI-28: Split evidence collection into enforced vs aspirational manifests
- **Priority:** P3
- **Effort:** M
- **Depends on:** AI-12, AI-13
- **Source:** MASTER-REVIEW.md "Strengths Worth Preserving" + OWASP "Must fix #2"

Partition the evidence-collection timers so `evidence-enforced.timer` emits only artifacts provable from Nix/systemd/kernel state (config hashes, unit properties, kernel params, audit log presence) and `evidence-aspirational.timer` emits the app-layer / policy-doc artifacts that depend on humans or on not-yet-built code. Assessors then see clearly what the infrastructure guarantees vs what depends on the app team. Ship both under `services.evidence-collection.*` NixOS options.
