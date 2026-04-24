# Architecture & Cross-Cutting TODOs

This section owns the foundational and systemic work for the `nix-flake` project: repository and flake scaffolding, cross-module canonical configuration, secrets management, evidence generation, boot integrity, threat model and data classification, RAG data-flow reconciliation, account lifecycle, and CI that catches broken Nix before modules diverge. These TODOs are prerequisites for or run parallel to the framework-specific work owned by the infrastructure and compliance agents; anything that touches more than one framework module or sets the shape of the repo lives here. Priorities are calibrated against the MASTER-REVIEW action plan: Systemic Issues #1–#3 and the "Immediate" items in the action plan are all P0.

---

### ARCH-01: Bootstrap flake skeleton and six-module layout
- **Priority:** P0
- **Effort:** M
- **Depends on:** none
- **Source:** prd.md §3.1–§3.2, wiki/architecture/flake-modules.md, MASTER-REVIEW.md "Before Phase 1 completion" #10

Create `flake.nix`, `flake.lock`, and the module tree (`modules/stig-baseline`, `modules/gpu-node`, `modules/lan-only-network`, `modules/audit-and-aide`, `modules/agent-sandbox`, `modules/ai-services`) with stubs that import each other in the dependency order defined in prd.md §3.2. Include one example host (`hosts/ai-server`) that composes all six modules so the flake evaluates end-to-end before any real config is written. Everything else in this list assumes this scaffold exists.

### ARCH-02: Extract Appendix A (Canonical Configuration Values) into a single source-of-truth module
- **Priority:** P0
- **Effort:** M
- **Depends on:** ARCH-01
- **Source:** prd.md Appendix A, MASTER-REVIEW.md "Systemic Issue #1", action plan item #2

Appendix A already resolves most cross-module conflicts in prose; the implementation must make it mechanically enforced. Create `modules/canonical/default.nix` exporting a single attrset (`canonical = { ssh = {…}; journal = {…}; tmpfiles = {…}; sysctl = {…}; … }`) that every other module imports rather than redeclaring. Every PRD module's inline Nix snippet is illustrative only — the flake references `canonical.*` so a change updates all frameworks at once. This is the structural fix for the duplication that already diverged across seven PRDs.

### ARCH-03: Add CI job that runs `nix flake check` and `nix eval` on every commit
- **Priority:** P0
- **Effort:** S
- **Depends on:** ARCH-01
- **Source:** MASTER-REVIEW.md "Systemic Issue #2", action plan items #1 and #14

17+ broken Nix snippets across the PRDs would fail evaluation today (phantom `security.protectKernelImage`, `pkgs.pam`, `Protocol 2`, deprecated `swapDevices.*.encrypted`, nftables/iptables collision, etc.). Stand up GitHub Actions (or equivalent) that runs `nix flake check`, `nix eval .#nixosConfigurations.ai-server.config.system.build.toplevel.drvPath`, `statix`, and `deadnix` on every PR. Without this gate, Systemic Issue #2 will recur as implementation proceeds.

### ARCH-04: Author the Resolved Settings Table as machine-readable data
- **Priority:** P0
- **Effort:** S
- **Depends on:** ARCH-02
- **Source:** prd.md Appendix A, MASTER-REVIEW.md "Systemic Issue #3", action plan item #9

MASTER-REVIEW Systemic Issue #3 calls for a table showing every setting whose frameworks disagree, the strictest resolution, and the driving framework. Appendix A has this narratively; convert it to a versioned `docs/resolved-settings.yaml` (or `.nix` attrset) that the canonical module imports and the evidence generator can emit. Implementers and auditors then see one authoritative answer instead of seven framework modules. Each row: `setting`, `value`, `driving_framework`, `rejected_values`, `rationale_link`.

### ARCH-05: Implement sops-nix secrets module (pick one, commit)
- **Priority:** P0
- **Effort:** M
- **Depends on:** ARCH-01
- **Source:** prd.md §7.13, wiki/shared-controls/secrets-management.md, MASTER-REVIEW.md "Master PRD must-fix #3", action plan item #5

Add `sops-nix` as a flake input and create `modules/secrets/default.nix` defining: age key provisioning procedure, per-secret declarations (TLS certs, SSH host keys, LUKS passphrase backup, API tokens, TOTP seeds, backup encryption keys), runtime paths under `/run/secrets/`, owner/group/mode per secret, and the rotation schedule from Appendix A §A.6 and wiki/shared-controls/secrets-management.md. Commit to sops-nix (not agenix) and delete the "either/or" prose from the PRD once chosen — leaving the decision open invites divergence. Every other module consumes secrets via `config.sops.secrets.<name>.path`.

### ARCH-06: Write nixos-agnostic path audit — strip `/usr/bin`, `/sbin`, `/usr/sbin` everywhere
- **Priority:** P0
- **Effort:** S
- **Depends on:** ARCH-01
- **Source:** MASTER-REVIEW.md action plan item #4, wiki/nixos-platform/nixos-gotchas.md §2, prd.md Appendix A.12

STIG audit rules, PCI FIM paths, and sudo `secure_path` across the PRDs still reference Linux-FHS paths that do not exist on NixOS. Before any module code lands, grep the PRD + any code-in-progress for `/usr/bin`, `/usr/sbin`, `/sbin`, `/usr/lib` and replace with `/run/current-system/sw/bin`, `/run/current-system/sw/sbin`, or Nix store paths. Add a lint rule (`grep -rn '/usr/bin' modules/ && exit 1`) to CI from ARCH-03 so regressions fail the build.

### ARCH-07: Secrets-in-Nix-store leakage lint
- **Priority:** P1
- **Effort:** S
- **Depends on:** ARCH-03, ARCH-05
- **Source:** wiki/nixos-platform/nixos-gotchas.md §1, wiki/shared-controls/secrets-management.md

`/nix/store` is world-readable. Add a CI check that scans evaluated derivations for common leakage patterns: `pkgs.writeText` or `builtins.toFile` containing anything that looks like a PEM block, API token, or plaintext password; `ExecStart` lines interpolating non-`/run/secrets` paths for secrets; environment variables on AI services containing secret-shaped values. Complements ARCH-05 by catching mistakes that sops-nix alone cannot prevent.

### ARCH-08: Codify threat model, data classification, and single-tenant declaration in-flake
- **Priority:** P1
- **Effort:** S
- **Depends on:** ARCH-01
- **Source:** prd.md §1.1, §7.16, §8, MASTER-REVIEW.md "Master PRD should-fix", wiki/architecture/threat-model.md

The threat model, four-tier data classification (Public/Internal/Sensitive/Restricted), and "single-tenant, single-operator" scope are in prose only. Create `modules/meta/default.nix` that exposes them as `config.system.compliance.{threatModel, dataClassification, tenancy}` options so downstream modules can gate behavior (e.g., an AI service refuses to handle a collection tagged `Sensitive` unless encryption and audit modules are enabled). This also becomes an evidence artifact — proof that classification is declared, not assumed.

### ARCH-09: Secure Boot / boot integrity shared module (lanzaboote)
- **Priority:** P1
- **Effort:** M
- **Depends on:** ARCH-01
- **Source:** prd.md §7.14, wiki/architecture/nix-implementation-patterns.md "Boot Security", MASTER-REVIEW.md STIG must-fix #5, Master PRD should-fix

Add `lanzaboote` as a flake input and wire it into `stig-baseline` with the canonical boot settings (Secure Boot on, `systemd-boot.editor = false`, `ctrlAltDelUnit = ""`, emergency/rescue require sulogin auth, tmpfs mount options `nosuid,nodev,noexec` on `/tmp`, `/dev/shm`, `/var/tmp`, IOMMU kernel params). Without boot integrity, LUKS is defeated by a bootloader swap — this is a foundational control missing from STIG/NIST today.

### ARCH-10: Evidence generation framework (shared systemd timer + activation script)
- **Priority:** P1
- **Effort:** M
- **Depends on:** ARCH-02, ARCH-04
- **Source:** prd.md §7.9, wiki/shared-controls/evidence-generation.md, MASTER-REVIEW.md NIST should-fix
- **Status:** ✓ PR #47

Build `modules/audit-and-aide/evidence.nix` that runs weekly via systemd timer AND on every `nixos-rebuild switch` via `system.activationScripts`. Collects: `getent passwd/group`, `nft list ruleset`, `auditctl -l`, `nix-store --query --requisites /run/current-system`, `nixos-rebuild list-generations`, `sshd -T`, `cryptsetup status`, `nix-store --verify`, `nix flake metadata --json`, `nixos-version`, `nix-info -m`, the resolved-settings YAML from ARCH-04, and a SHA-256 manifest. Writes to `/var/lib/compliance-evidence/YYYYMMDD/` (permissions 0750 root:root per A.11). Every framework agent reuses this hook instead of rolling its own.

### ARCH-11: Account lifecycle module (declarative users, rotation, access review)
- **Priority:** P1
- **Effort:** M
- **Depends on:** ARCH-05
- **Source:** prd.md §7.15, MASTER-REVIEW.md Master PRD should-fix
- **Status:** ✓ PR #TBD

Create `modules/accounts/default.nix` enforcing `users.mutableUsers = false`, declaring interactive users with SSH key references pulled from sops-nix, and exposing options for quarterly access review (emits a report into the evidence directory listing all accounts, groups, last-login timestamps, and key ages). Include deprovisioning procedure docs and automated TOTP seed rotation hooks. Removes the "HITRUST says 15 chars, PCI says 12" ambiguity by centralizing on Appendix A.6.

### ARCH-12: Reconcile RAG data flow across master PRD and implementation
- **Priority:** P1
- **Effort:** S
- **Depends on:** ARCH-08
- **Source:** prd.md §6.4, MASTER-REVIEW.md Master PRD must-fix #4

Master PRD §6.4 added a RAG pipeline block, but the framework modules and the `ai-services` design still treat inference as the only path. Author `docs/data-flows/rag.md` that walks ingestion → embedding → vector store → retrieval → context assembly → inference → output, naming the Nix-level controls at each step (access-control per collection, AIDE monitoring of the vector store path from A.12, per-requestor context filtering, source-citation logging). Flag which controls are enforceable by NixOS and which require application code, mirroring the OWASP residual-risk pattern.

### ARCH-13: Residual-risk / "what infrastructure cannot solve" appendix
- **Priority:** P1
- **Effort:** S
- **Depends on:** ARCH-08
- **Source:** MASTER-REVIEW.md OWASP must-fix #1–#2, HIPAA must-fix #1, wiki/architecture/threat-model.md

Write `docs/residual-risks.md` enumerating every control the flake cannot fully enforce: live-memory ePHI in RAM/VRAM (AMD SEV / Intel TDX not available), GPU VRAM residue post-inference, prompt injection (application layer), cgroups cannot limit VRAM, Ollama watchdog unsupported, model provenance is trust-on-first-download not cryptographic, semantic attacks on LLM outputs, kernel exploits bypassing systemd sandbox. Each residual risk names its driving framework and the compensating control or accepted risk. Referenced from every framework module so reviewers stop getting false confidence.

### ARCH-14: Log-forwarding module (remote syslog over TLS)
- **Priority:** P2
- **Effort:** M
- **Depends on:** ARCH-05, ARCH-10
- **Source:** MASTER-REVIEW.md PCI must-fix #3, HIPAA should-fix, action plan item #12

PCI 10.3.3, HIPAA §164.312(e), and HITRUST all require centralized log forwarding; local-only journald does not satisfy them. Add rsyslog or vector with RELP/syslog-over-TLS, certs sourced from sops-nix, forwarding journald + auditd + ai-audit to an external collector. Because no module owns this today, it's cross-cutting. Replaces the cleartext-TCP rsyslog configuration the HIPAA module currently ships.

### ARCH-15: Flake-lock update cadence and vulnix CVE scanning
- **Priority:** P2
- **Effort:** S
- **Depends on:** ARCH-03
- **Source:** prd.md §11 Risk #8, Appendix A.8, MASTER-REVIEW.md action plan item #13

Add a scheduled CI job (weekly) that runs `nix flake update`, `vulnix --system`, and opens a PR with the diff + CVE deltas. Include a documented cadence policy (critical CVE = emergency update, otherwise weekly merge window). Prevents the "locked flake accumulates unpatched CVEs" risk called out in §11 without surprising operators with silent rolls. Note: `vulnix` output is not JSON despite how the NIST module labeled it — capture as `.txt` or parse explicitly.

### ARCH-16: Module boundary lints — prevent cross-module attribute collisions
- **Priority:** P2
- **Effort:** S
- **Depends on:** ARCH-02, ARCH-03
- **Source:** MASTER-REVIEW.md "Systemic Issue #1", wiki/architecture/nix-implementation-patterns.md "Key Takeaways"

Enforce in CI that certain options are declared by exactly one module: `boot.blacklistedKernelModules`, `boot.kernel.sysctl`, `systemd.tmpfiles.rules`, `networking.firewall`, `security.pam.services.<name>.text`. Use `lib.mkMerge` deliberately where intentional, `lib.mkForce` sparingly and commented. A simple grep-based check plus a Nix assertion in the canonical module is enough for Phase 1. Stops the six-module flake from rediscovering the seven-PRD conflict problem at code level.

### ARCH-17: Acceptance-criteria test harness (prd.md §10 → automated checks)
- **Priority:** P2
- **Effort:** L
- **Depends on:** ARCH-10
- **Source:** prd.md §10, MASTER-REVIEW.md Master PRD must-fix #5, action plan item #8

prd.md §10's 18 acceptance criteria are prose. Translate each into a `nixosTest` or a shell assertion run post-rebuild: port-allowlist scan, SSH config check, LUKS status, AIDE alert-fires-on-change, sandbox escape attempts, rate-limit 429 at 31 req/min, secret-not-in-store grep of `/nix/store`, evidence snapshot diff, generation-rollback drill. Produces a pass/fail report alongside the evidence bundle. Framework agents can reuse the harness for their own control-level tests.

### ARCH-18: Quarterly review cadence doc + framework version pins
- **Priority:** P3
- **Effort:** S
- **Depends on:** ARCH-04
- **Source:** prd.md §11 Risk #9, MASTER-REVIEW.md action plan item #13

Write `docs/review-cadence.md` listing what must be re-validated each quarter: MITRE ATLAS technique IDs, Ollama internals and storage format, NixOS release notes (breaking options), HITRUST CSF version, PCI DSS version, EU AI Act updates. Pin the exact framework versions in the flake's meta module (from ARCH-08) so "we are compliant with X" is a versioned statement, not a moving target. Low priority but cheap and prevents silent drift post-Phase 3.
