# Master Review

7 domain-specific expert agents reviewed 8 files (~475KB, ~10,266 lines). **Overall: 6.8/10.**

## Three Systemic Problems

### 1. Inline Code Duplication (CRITICAL)
Every module embeds Nix snippets that duplicate and diverge from other modules. `MaxRetentionSec` has 6 different values across modules. SSH hardening appears in 4+ places with different ciphers.

**Resolution:** [[compliance-frameworks/canonical-config-values]] is now the single source of truth.

### 2. Broken NixOS Code (CRITICAL)
17+ code issues would cause eval failures, broken services, or security misconfigurations on real NixOS. See [[nixos-platform/nixos-gotchas]] for the full list.

**Resolution:** Every snippet must be validated against NixOS 24.11+ before implementation.

### 3. No Cross-Framework Conflict Resolution (HIGH)
Seven modules gave seven different answers for the same setting.

**Resolution:** Master PRD Appendix A resolves all conflicts to strictest applicable value.

## Per-Module Scores

| Module | Score | Verdict |
|---|---|---|
| Master PRD | 7.1 | Good umbrella, canonical appendix added |
| NIST 800-53 | 7.0 | Strong mapping, broken iptables/phantom options |
| HIPAA | 6.9 | Thorough, but understates [[hipaa/live-memory-ephi-risk]] |
| HITRUST | 6.1 | Wrong domain count (14 vs 19), unrealistic maturity |
| PCI DSS | 7.1 | Best quality, needs network vuln scanner |
| OWASP | 6.8 | Strong systemd controls, blurs infra/app boundary |
| AI Governance | 6.5 | Good coverage, broken model fetch + WatchdogSec |
| STIG | 6.5 | Comprehensive findings, wrong audit paths |

## Strengths Worth Preserving

- NixOS as compliance platform — declarative, immutable, reproducible
- Honest scope boundaries — clearer than most enterprise programs
- Evidence generation automation — few organizations attempt this
- Cross-framework mapping — high-value for multi-certification
- Agent sandboxing via systemd — genuinely strong infrastructure
- Module separation — prevents monolithic compliance doc failure

## Key Takeaways

- The foundation is solid — issues are fixable
- Stop code duplication from spreading — [[compliance-frameworks/canonical-config-values]] is canonical
- Be brutally honest about [[ai-security/ai-security-residual-risks|what infrastructure cannot solve]]
- HITRUST needs the most rework (wrong domain taxonomy, unrealistic maturity claims)
