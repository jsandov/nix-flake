# Master Review Findings — Critical Issues and Lessons Learned

Source: MASTER-REVIEW.md (7 domain-specific expert agents reviewed 8 files, ~475KB, ~10,266 lines)

**Overall Score: 6.8/10** — solid architectural vision, needs technical verification pass and structural refactoring.

## Three Systemic Problems

### 1. Inline Code Duplication Causing Conflicts (CRITICAL)

Every module file contains inline Nix code that duplicates and diverges from other modules:
- `MaxRetentionSec` specified as 90day, 365day, 1year, 18month, 26280h, and 7776000 across modules
- SSH hardening appears in 4+ modules with different cipher lists
- `NoNewPrivileges` appears 19 times; `PasswordAuthentication = false` appears 6 times
- `boot.blacklistedKernelModules` in multiple modules with different lists
- `systemd.tmpfiles.rules` would cause attribute collisions in real flake

**Fix:** Canonical Configuration Values appendix in master PRD resolves every conflict. Module files reference by pointer, not embed their own snippets.

### 2. NixOS Code That Won't Evaluate (CRITICAL)

| Issue | Impact |
|---|---|
| iptables rules with mutually exclusive DROP clauses | System unreachable |
| `security.protectKernelImage = true` — doesn't exist | Eval failure |
| `Protocol = 2` in SSH — removed in OpenSSH 7.6 | sshd fails to start |
| `pkgs.pam` — doesn't exist in nixpkgs | Eval failure |
| `OLLAMA_HOST = "0.0.0.0:11434"` — binds all interfaces | Security violation |
| Audit rules monitor `/usr/bin/sudo` — path doesn't exist on NixOS | Rules monitor nothing |
| `MemoryDenyWriteExecute=true` with CUDA | Inference broken |
| `WatchdogSec=300` for Ollama — doesn't support sd_notify | Spurious kills |
| NixOS 24.11 defaults to nftables — iptables syntax may fail | Firewall broken |

**Fix:** Every Nix snippet must be validated against real NixOS 24.11+ evaluation before finalization.

### 3. No Conflict Resolution Between Frameworks (HIGH)

Implementer reading 7 modules finds 7 different answers for the same setting. The master PRD's Appendix A now resolves these conflicts.

## Per-Module Scores and Critical Findings

| Module | Score | Key Issues |
|---|---|---|
| Master PRD | 7.1 | Needed canonical config appendix (now added) |
| NIST 800-53 | 7.0 | Broken iptables, phantom NixOS options, alerting bugs |
| HIPAA | 6.9 | Understatement of live-memory ePHI risk, CUDA incompatibility |
| HITRUST | 6.1 | Wrong domain taxonomy (14 vs actual 19), unrealistic maturity |
| PCI DSS | 7.1 | Best quality; needs ClamAV on-access, network vuln scanner |
| OWASP | 6.8 | Strong systemd controls; blurs infra vs app boundary |
| AI Governance | 6.5 | Model fetch script won't work, WatchdogSec breaks Ollama |
| STIG | 6.5 | Audit rules monitor wrong paths, deprecated SSH options |

## Key Lessons Learned

1. **NixOS paths are different** — `/usr/bin`, `/usr/sbin`, `/sbin` don't exist. Use `/run/current-system/sw/bin/`
2. **nftables is the default** — NixOS 24.11+ uses nftables. Don't use iptables `extraCommands`
3. **CUDA breaks MemoryDenyWriteExecute** — GPU inference needs W+X memory for JIT compilation
4. **Ollama doesn't support sd_notify** — use timer-based health checks, not WatchdogSec
5. **Ollama stores models as content-addressed blobs** — not `.bin` files. `find -name "*.bin"` finds nothing
6. **Single source of truth is critical** — PRD modules define requirements, Appendix A defines resolved config
7. **Be honest about infrastructure limits** — ~60% of OWASP controls require custom application code
8. **OpenSSH deprecated options cause failures** — `Protocol 2`, `ChallengeResponseAuthentication` break sshd

## Recommended Action Plan

### Immediate (before implementation)
1. Validate all Nix code against real NixOS 24.11+ evaluation
2. Create Canonical Configuration Values appendix (done)
3. Fix HITRUST domain taxonomy to actual 19-domain CSF v11
4. Fix NixOS-specific audit paths throughout

### Before Phase 1
5. Add secrets management module (sops-nix or agenix)
6. Add Residual Risk sections to OWASP and HIPAA
7. Write referenced policy documents
8. Fix model supply chain verification for Ollama blob format

### Ongoing
- Quarterly ATLAS technique ID verification
- CI job evaluating combined Nix config on every commit
