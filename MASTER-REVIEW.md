# Master Review: Control-Mapped NixOS AI Agentic Server PRD Suite

**Review Date**: 2026-04-22
**Documents Reviewed**: 8 files, ~475KB, ~10,266 lines
**Reviewers**: 7 domain-specific expert agents (NIST, HIPAA, HITRUST, PCI QSA, OWASP/AI Security, AI Governance, Security Architecture)

---

## Executive Summary

The PRD suite is a **strong first draft** that demonstrates genuine understanding of each framework and makes a compelling case for NixOS as a compliance platform. The architecture is sound, scope boundaries are honest, and module-level detail is genuinely useful for implementation.

However, the suite has **three systemic problems** that must be fixed before implementation begins, and **per-module technical issues** that would cause build failures or security misconfigurations if the Nix code is applied directly.

**Overall Score: 6.8/10** — solid architectural vision, needs a technical verification pass and structural refactoring.

| Module | Score | Verdict |
|---|---|---|
| Master PRD (`prd.md`) | 7.1 | Good umbrella, needs canonical config appendix |
| NIST 800-53 | 7.0 | Strong mapping, broken iptables and phantom NixOS options |
| HIPAA | 6.9 | Thorough safeguards, dangerous understatement of live-memory ePHI risk |
| HITRUST | 6.1 | Wrong domain taxonomy (14 vs actual 19), unrealistic maturity claims |
| PCI DSS v4.0 | 7.1 | Best overall quality, anti-malware argument needs strengthening |
| OWASP LLM + Agentic | 6.8 | Strong systemd controls, blurs infrastructure vs application boundary |
| AI Governance | 6.5 | Good framework coverage, model supply chain code won't work |
| STIG/DISA | 6.5 | Comprehensive findings, audit rules monitor wrong NixOS paths |

---

## Systemic Issue #1: Inline Code Duplication Causing Conflicts

**Severity: Critical — blocks implementation**

Every module file contains inline Nix code that partially duplicates code from other modules. These have **already diverged before any real code exists**:

- `MaxRetentionSec` is specified as `90day` (NIST, STIG), `365day` (HITRUST), `1year` (AI governance), `18month` (AI governance Section 2.3), `26280h` (HIPAA), and `7776000` seconds (NIST alternate section)
- SSH hardening appears in 4+ modules with different cipher lists, MAC selections, and option paths
- `NoNewPrivileges` appears 19 times; `PasswordAuthentication = false` appears 6 times
- `boot.blacklistedKernelModules` appears in multiple modules with overlapping but different lists
- `systemd.tmpfiles.rules` defined separately in multiple sections — would cause attribute collisions in a real flake

**Fix**: Add a **Canonical Configuration Values** appendix to `prd.md` that resolves every conflict to the strictest applicable value. Restructure module files to reference that appendix by pointer, not embed their own Nix snippets. The implementation flake is the single source of truth; PRD modules define *requirements*, not *config*.

---

## Systemic Issue #2: NixOS Code That Won't Evaluate

**Severity: Critical — code is broken**

Across all modules, reviewers identified NixOS configuration that would fail on a real system:

| Issue | Module(s) | Impact |
|---|---|---|
| iptables rules with mutually exclusive DROP clauses — blocks ALL traffic | NIST | System unreachable |
| `security.protectKernelImage = true` — option does not exist | NIST | Eval failure |
| `Protocol = 2` in SSH — removed in OpenSSH 7.6, NixOS ships 9.x | STIG | sshd fails to start |
| `pkgs.pam` — package does not exist in nixpkgs | STIG | Eval failure |
| PAM config mixes `.text` override with structured options — mutually exclusive | STIG | Auth broken |
| `environment.etc."login.defs".text` — conflicts with NixOS shadow package | STIG | Eval failure |
| `notify-admin@` template unit uses `$1` not `%i` — never receives instance name | NIST | Silent alerting failure |
| `OLLAMA_HOST = "0.0.0.0:11434"` — binds all interfaces, contradicts LAN-only | STIG | Security violation |
| Audit rules monitor `/usr/bin/sudo`, `/usr/sbin/useradd` — paths don't exist on NixOS | STIG | Rules monitor nothing |
| `services.xserver.videoDrivers` set without enabling xserver or `hardware.nvidia` | NIST | No GPU |
| `MemoryDenyWriteExecute=true` with CUDA — CUDA requires W+X for JIT | HIPAA | Inference broken |
| `OLLAMA_NOPRUNE=1` described as security control — it's a storage flag | HIPAA | Misleading |
| AIDE alerting uses `$SERVICE_RESULT` in separate unit — variable not available | HIPAA | Alerting broken |
| `WatchdogSec=300` for Ollama — Ollama doesn't support sd_notify | AI Gov | Spurious kills |
| Approval gate at `/opt/ai/approval-gate-server.py` — outside Nix-managed boundary | AI Gov | Unreproducible |
| `vulnix` output redirected to `.json` — output is not JSON | NIST | Misleading evidence |
| NixOS 24.11 defaults to nftables — `extraCommands` with iptables syntax may fail | HITRUST | Firewall broken |
| `ssl_ciphers HIGH:!aNULL:!MD5:!RC4` — includes CBC-mode ciphers vulnerable to padding oracle | HIPAA | Weak TLS |
| `openssl.cnf` sets `fips=yes` without FIPS provider loaded — breaks OpenSSL | STIG | TLS broken |

**Fix**: Every Nix snippet must be validated against a real NixOS 24.11+ evaluation before the PRD is finalized. Consider adding a CI job that evaluates the combined config.

---

## Systemic Issue #3: No Conflict Resolution Between Frameworks

**Severity: High — causes implementation confusion**

Multiple frameworks impose different requirements for the same setting with no reconciliation:

| Setting | NIST | HIPAA | HITRUST | PCI DSS | STIG |
|---|---|---|---|---|---|
| Log retention | 90 days | 6 years (policy docs) | 1 year | 1 year (3mo available) | 90 days |
| Password min length | "appropriate" | — | 15 chars | 12 chars (v4.0) | 15 chars |
| Patch timeline (critical) | "timely" | "reasonable" | 15–30 days | 30 days | per ATO |
| MFA scope | privileged access | addressable | Level 2+ | all CDE access | privileged remote |
| Scan frequency | "regularly" | — | monthly | quarterly (ASV) | per ATO |

The master PRD says "resolve toward the strictest applicable requirement" but never actually does so. An implementer reading 7 different modules will find 7 different answers.

**Fix**: Add a **Resolved Settings Table** to `prd.md` that lists every setting with conflicting values, the strictest resolution, and which framework drove the decision.

---

## Per-Module Critical Findings

### NIST 800-53 (7.0/10)

**Must fix:**
1. lan-only-network iptables rules have mutually exclusive DROP clauses — will deny ALL traffic
2. `security.protectKernelImage` is a phantom NixOS option — remove
3. `notify-admin@` template unit uses `$1` instead of `%i` — alerting silently fails
4. SC-8 (TLS for APIs) has no implementation despite being Moderate baseline mandatory
5. IA-2(1) MFA is marked Critical but has zero concrete config

**Should fix:**
- IA-11 mismapped — `ClientAliveInterval` is session termination, not re-authentication
- AC-14 missing entirely
- AU-10 (Non-Repudiation) absent — relevant for agent action attribution
- Evidence collection should run weekly + on every `nixos-rebuild switch`, not just monthly

### HIPAA (6.9/10)

**Must fix:**
1. Live memory ePHI exposure (RAM + VRAM) gets one sentence — this is the single largest risk and needs explicit risk acceptance or mitigation strategy (AMD SEV / Intel TDX)
2. AIDE alerting code is broken (`$SERVICE_RESULT` unavailable in separate unit)
3. `MemoryDenyWriteExecute=true` incompatible with CUDA — will break inference
4. Missing §164.316 (Policies and Documentation Requirements) — a Required standard
5. Missing Privacy Rule individual rights (§164.524/526/528) — accounting of disclosures for AI processing of ePHI

**Should fix:**
- Core dumps not addressed — segfaulting inference dumps ePHI to disk. Add `systemd.coredump.extraConfig = "Storage=none"`
- `OLLAMA_NOPRUNE=1` is not a security control — remove
- rsyslog uses TCP without TLS — transmitting logs in cleartext violates §164.312(e)
- Breach monitor parsing `journalctl -f` with grep loop — silently stops on pipe break
- No breach definition for this specific system (what constitutes a breach vs. incident?)
- Nix store leakage vector not warned about

### HITRUST (6.1/10)

**Must fix:**
1. **Domain taxonomy is wrong** — HITRUST CSF v11 uses 19 domains (0–18), not 14. Document appears to work from a summary, not MyCSF
2. Maturity Level 5 claim for any domain in Year 1 is not credible — will draw immediate QA scrutiny
3. `pam_pwhistory` with `remember=24` is claimed but never actually configured
4. Critical patch remediation timeline incorrect — Level 2 is 30 days, not 15
5. Physical security, incident management, BCP, and privacy domains are missing or inadequate

**Should fix:**
- Map to MyCSF requirement statement IDs, not just domain names
- Drop all Year-1 maturity claims above Level 3
- Fix NixOS PAM option syntax (`services.<name>.rules.password` doesn't match NixOS structure)
- Write the `/docs/policies/` documents that are referenced but don't exist
- Scoped-out controls should be marked N/A, not scored at maturity level

### PCI DSS v4.0 (7.1/10)

**Must fix:**
1. Anti-malware: ClamAV excludes `/nix/store` entirely AND has no on-access scanning — add `clamonacc` for writable paths
2. Vulnerability scanning: `vulnix` is not a network vulnerability scanner. QSA expects OpenVAS/Nessus/Qualys-class authenticated scanning
3. Missing centralized log forwarding config — local-only logs fail Req 10.3.3
4. Automated log review is a shell script checking `failure_count > 10` — too primitive for 10.4.1.1

**Should fix:**
- GPU VRAM CHD residue not addressed in scoping section
- No connected-to-system reduced requirements analysis
- Segmentation test only checks 3 hardcoded IPs — should enumerate CDE ranges dynamically
- TOTP seed file (`~/.google_authenticator`) protection not addressed
- FIM paths include `/usr/bin` and `/usr/sbin` which are empty on NixOS — need NixOS-aware paths
- No CVSS-based remediation timelines for discovered vulnerabilities

### OWASP LLM + Agentic (6.8/10)

**Must fix:**
1. Add explicit **"Residual Risk and Known Limitations"** section — the document creates false confidence that infrastructure controls handle semantic attacks
2. State clearly: **~60% of listed controls require custom application code that doesn't exist** — distinguish enforced (NixOS) vs aspirational (app layer)
3. GPU memory is a blind spot — cgroups cannot enforce VRAM limits
4. Monitoring strategy claims to detect prompt injection from infrastructure logs — it cannot

**Should fix:**
- LLM09 (Misinformation) confidence gating is hand-waving — Ollama doesn't expose calibrated log probabilities
- LLM04 (Poisoning) "sample outputs for known-poisoning indicators" is unactionable without defining indicators
- AGT-06 validator agent is itself an LLM subject to hallucination — acknowledge
- Model provenance is trust-on-first-download, not true cryptographic provenance — say so
- FDE mapped to LLM08 (Embedding Weaknesses) is misleading — FDE doesn't prevent embedding manipulation
- No log volume sizing estimate for full prompt/completion logging

### AI Governance (6.5/10)

**Must fix:**
1. `ai-model-fetch` script won't work — Ollama stores models as content-addressed blobs, not `.bin` files. `find -name "*.bin"` finds nothing
2. `WatchdogSec=300` on Ollama without sd_notify support — causes spurious service kills
3. Approval gate server at `/opt/ai/approval-gate-server.py` is outside the Nix-managed reproducible boundary
4. Add a **tiered implementation guide** — the full organizational burden (17 AI-ORG processes) is unrealistic for a single operator

**Should fix:**
- ATLAS technique IDs need verification against current ATLAS release (T0024/T0043 descriptions may be stale)
- EU AI Act Article 12 logging assumes structured per-request records that Ollama doesn't produce
- ISO 42001 A.6.2 data governance points to a thin section — RAG needs lineage tracking, versioning, quality metrics
- Emerging frameworks section adds no unique controls — could be halved to an appendix
- No priority ordering in the combined control matrix

### STIG/DISA (6.5/10)

**Must fix:**
1. **Audit rules monitor `/usr/bin/sudo`, `/usr/sbin/useradd`** — these paths don't exist on NixOS. Must use `/run/current-system/sw/bin/` or Nix store paths
2. `Protocol = 2` removed from OpenSSH in 7.6 — will break sshd on NixOS
3. `pkgs.pam` doesn't exist in nixpkgs — eval failure
4. `OLLAMA_HOST = "0.0.0.0:11434"` binds all interfaces — contradicts LAN-only
5. Missing: Secure Boot, bootloader password, mount options (nosuid/nodev/noexec), Ctrl-Alt-Del disable, emergency mode auth, coredump restrictions, centralized syslog

**Should fix:**
- PAM configuration mixes `.text` with structured options — mutually exclusive approaches
- `environment.etc."login.defs".text` conflicts with NixOS shadow package management
- Duplicate `kernel.sysrq = 0` entries
- Missing kernel params: `tcp_timestamps`, `core_pattern`, `panic_on_oops`, `tcp_rfc1337`, `io_uring_disabled`
- Missing audit syscalls: `personality()`, `ptrace`, `open_by_handle_at`, failed access attempts
- Thunderbolt/USB4 DMA protection via IOMMU not addressed
- CHACHA20-POLY1305 in TLS contradicts FIPS-only stance in FIPS section
- Evidence script missing `nixos-version`, `nix-info -m`, and active flake lock hash

### Master PRD (7.1/10)

**Must fix:**
1. Add **Canonical Configuration Values** appendix resolving all cross-module conflicts
2. Add **Resolved Settings Table** for every setting with conflicting framework values
3. Add a secrets management strategy (sops-nix / agenix / vault) — currently no mechanism defined
4. Add RAG data flow — missing from master despite being a fundamentally different path than direct inference
5. Make acceptance criteria quantitative — "rate limiting is enforced" needs thresholds; "MFA required" needs the mechanism named

**Should fix:**
- State the threat model explicitly — who is the adversary, what is the crown jewel data
- Declare single-tenant/single-operator explicitly — multi-tenancy changes everything
- Add Secure Boot / boot integrity as a shared requirement
- Add account lifecycle management (access review, deprovisioning, credential rotation)
- Add data classification scheme — each module invents its own notion of "sensitive data"
- Start control matrix in Phase 1 of delivery plan, not Phase 3
- Split Phase 2 — `gpu-node` should be validated independently before `ai-services`
- Add risk for NixOS upstream breakage (rolling distro + locked flake = stale CVEs)
- Add risk for compliance framework version drift

---

## Recommended Action Plan

### Immediate (before any implementation)

1. **Validate all Nix code** against a real NixOS 24.11+ `nix eval` — fix every broken snippet
2. **Create the Canonical Configuration Values appendix** — resolve every cross-module conflict to a single value
3. **Fix the HITRUST domain taxonomy** — adopt the actual 19-domain CSF v11 structure from MyCSF
4. **Fix NixOS-specific audit paths** — replace `/usr/bin/*` with `/run/current-system/sw/bin/*` throughout

### Before Phase 1 completion

5. **Add secrets management module** — define sops-nix or agenix integration
6. **Add Residual Risk sections** to OWASP and HIPAA modules — be honest about what infrastructure can't solve
7. **Write the policy documents** referenced by HITRUST and NIST modules
8. **Fix the model supply chain verification** — align with actual Ollama blob storage format

### Before Phase 3 completion

9. **Add the Resolved Settings Table** to the master PRD
10. **Restructure module files** to reference canonical config by pointer, not inline duplication
11. **Add log volume sizing estimates** and storage capacity planning
12. **Implement centralized log forwarding** (remote syslog with TLS) across all modules

### Ongoing

13. **Quarterly review** of ATLAS technique IDs, Ollama internals, and framework version updates
14. **CI job** that evaluates the combined Nix config on every commit to catch regressions

---

## Strengths Worth Preserving

Despite the issues, the suite has genuine strengths that most compliance documentation lacks:

- **NixOS as a compliance platform** — the declarative, immutable, reproducible model structurally satisfies controls that are traditionally painful (CM-2, CM-6, SI-7, change management)
- **Honest scope boundaries** — the in-scope/out-of-scope split is clearer than most enterprise compliance programs
- **Evidence generation automation** — few organizations even attempt automated evidence collection
- **Cross-framework mapping** — having every control traced to multiple frameworks is high-value for multi-certification programs
- **Agent sandboxing via systemd** — the UID-per-agent model with InaccessiblePaths, NoExecPaths, and cgroup limits is a genuinely strong infrastructure foundation
- **Module separation** — framework-specific documents prevent the common failure mode of a single monolithic compliance doc that no one reads

The foundation is solid. The issues are fixable. The priority is: stop the code duplication from spreading, fix the broken Nix, and be brutally honest about what infrastructure alone cannot solve.
