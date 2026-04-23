# Lessons Learned

Key lessons from the PRD development and review process.

## NixOS-Specific Lessons

1. **NixOS paths are different** — `/usr/bin` doesn't exist. Audit rules and AIDE must use `/run/current-system/sw/bin/`
2. **nftables is the default** — NixOS 24.11+. Never use iptables `extraCommands`
3. **Nix store is world-readable** — secrets management (sops-nix/agenix) is non-negotiable
4. **Validate every snippet** — 17+ broken code issues found across modules

## AI/GPU-Specific Lessons

5. **CUDA breaks MemoryDenyWriteExecute** — GPU inference needs W+X memory for JIT
6. **Ollama doesn't support sd_notify** — use timer-based health checks, not WatchdogSec
7. **Ollama stores models as content-addressed blobs** — not `.bin` files
8. **Ollama has no structured per-request logging** — app-layer middleware required for EU AI Act
9. **GPU VRAM is outside cgroup control** — can't enforce VRAM limits from OS

## Compliance Process Lessons

10. **Single source of truth is critical** — code duplication across modules causes divergence immediately
11. **Resolve conflicts explicitly** — "strictest applicable" needs an actual resolved table, not a principle
12. **~60% of OWASP controls need application code** — be honest about what infrastructure alone cannot do
13. **OpenSSH deprecated options cause failures** — `Protocol 2` and `ChallengeResponseAuthentication` break sshd
14. **HITRUST CSF v11 has 19 domains, not 14** — work from MyCSF, not summaries
15. **Maturity Level 5 in Year 1 is not credible** — assessors will flag this immediately

## Architecture Lessons

16. **Module separation prevents monolithic failure** — each framework gets its own PRD
17. **Evidence generation should be automated from day one** — not Phase 3
18. **Split Phase 2** — validate gpu-node independently before building ai-services on top
19. **Control matrix belongs in Phase 1** — it's the traceability backbone

## Key Takeaways

- Most lessons are about NixOS being different from traditional Linux, not NixOS being wrong
- The biggest meta-lesson: compliance-as-code works, but only if you validate the code
- Start with [[shared-controls/shared-controls-overview]] — they satisfy the most frameworks per unit of effort
- Review [[compliance-frameworks/canonical-config-values]] before writing any Nix — it prevents the duplication problem
