# Lessons Learned

Key lessons from the PRD development and review process.

## NixOS-Specific Lessons

1. **NixOS paths are different** — `/usr/bin` doesn't exist. Audit rules and AIDE must use `/run/current-system/sw/bin/`
2. **nftables is the default** — NixOS 24.11+. Never use iptables `extraCommands`
3. **Nix store is world-readable** — secrets management ([[../shared-controls/secrets-management|sops-nix]]) is non-negotiable; agenix is not supported
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

## Implementation Bring-Up Lessons (ARCH-01 → ARCH-04)

Process-level lessons from the first four P0 TODOs landing — orthogonal to the PRD-phase lessons above.

20. **When there is no local `nix` CLI, CI *is* the evaluator.** Write Nix conservatively, push, let [[../architecture/ci-gate]] surface the errors in 1–2 minutes. Budget for ≥1 iteration on every non-trivial PR. Four iterations on the skeleton PR wasn't a failure mode — it was how broken patterns revealed themselves one layer at a time.
21. **Supply-chain drift in CI actions is fast.** `DeterminateSystems/magic-nix-cache-action` changed between 2024 (zero-config) and 2026 (requires FlakeHub auth) with no workflow-visible signal. Pin action versions to commit SHAs and re-verify the stack every 6 months. See [[../nixos-platform/github-actions-nix-stack]].
22. **One concept, two artifacts — audit vs runtime.** A cross-framework resolution lives in a Nix-consumable module (`canonical.nix`) *and* an audit-consumable YAML (`resolved-settings.yaml`). Neither audience can use the other's format. See [[../shared-controls/canonical-config]]. Expect this pattern to repeat for evidence generation, threat model, and the model registry.
23. **PR cadence: one P0 per PR, batch wiki compiles.** Granular PRs clear CI faster, review more cleanly, and avoid CI-cache contention. Wiki compiles are cheap enough to batch 2–3 TODOs per compile PR.
24. **Prefer a lint over a one-shot audit.** ARCH-06's goal ("strip `/usr/bin` everywhere") was 80% preempted by a five-line grep in the CI workflow. When a TODO is primarily about "don't let X happen," a permanent lint beats a manual sweep — the lint keeps working forever.

## Key Takeaways

- Most lessons are about NixOS being different from traditional Linux, not NixOS being wrong
- The biggest meta-lesson: compliance-as-code works, but only if you validate the code
- CI is not a gate; it is a tight feedback loop. Plan for iteration.
- Start with [[../shared-controls/shared-controls-overview]] — they satisfy the most frameworks per unit of effort
- Review [[../shared-controls/canonical-config]] before writing any Nix — it prevents the duplication problem
