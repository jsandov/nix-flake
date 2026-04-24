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
25. **Never trust `gh run watch --exit-status` as the sole merge gate.** ARCH-05 (PR #26) landed broken on main despite the watch command returning exit 0. The watched run reported `conclusion: FAILURE` — the watch command disagreed with reality. Always check `gh pr view <n> --json statusCheckRollup` directly before `gh pr merge`, regardless of what watch returned. Hotfix PR #27 pinned sops-nix to restore main; raw note records the gap.
26. **Flake inputs without a rev are time bombs.** `url = "github:Mic92/sops-nix"` resolved to master and started pulling `buildGo125Module` when sops-nix upstream bumped Go versions and dropped nixos-24.11 compatibility. See [[../nixos-platform/nixos-gotchas#15-flake-inputs-tracking-mainline-break-silently]]. Every flake input that gates the build gets a commit SHA. No exceptions.
27. **Two-layer lint pattern: broad-for-code, narrow-for-docs.** ARCH-06 showed the shape. `modules/` and `hosts/` get a broad regex (`/usr/bin/` anywhere is a bug). `docs/` gets a narrow regex (`"-w /usr/bin/...` — the quoted audit-rule syntax) because PRD prose legitimately names the forbidden path in warnings and shebangs. Test for deciding: would the regex fire on the comment that explains the rule? If yes, lint is impossible — do a sweep. See [[../architecture/ci-gate#when-to-lint-vs-when-to-sweep]] and [[../nixos-platform/nixos-audit-rule-paths]].
28. **PRD-sweep TODO shape — grep, categorise, fix, lint-or-skip.** ARCH-06, INFRA-03, and INFRA-01+02 all followed the same procedure: (1) grep the PRD tree for the broken pattern; (2) categorise hits into broken-config / descriptive-prose / shebangs / MASTER-REVIEW historical; (3) fix broken-config hits using the canonical replacement; (4) add a narrow lint if the shape allows it. 15–30 min per sweep once the pattern is known. ARCH-03 backstops any misses.
29. **Pre-check TODO status with grep before claiming.** AI-06 ("Lock OLLAMA_HOST to loopback") was silently satisfied by earlier sweeps — every current reference was already `127.0.0.1`. Grep the target pattern first; if only historical references remain, close the bead with a note. Same rule for module-construction TODOs: check whether `canonical.*` already exposes the option you need before extending it.
30. **Three-tier PRD snippet convention.** Load-bearing (`prd.md` Appendix A, `modules/canonical/*`, `resolved-settings.yaml`, real `modules/*` code) must agree byte-for-byte on canonical values. Illustrative (framework-specific PRDs) must evaluate but may use placeholders. Reference (wiki code blocks) is short and focused. Mixing tiers produces the "snippet says X but implementation does Y" divergence. See [[../architecture/prd-snippet-tiers]].
31. **Granular PRs beat mega-PRs once CI is fast.** At ~3 min/CI run, opening a PR costs less than the context-switch cost of reviewing a large one. 15 merged PRs this session beat 3 mega-PRs across every measurable axis: faster CI, tighter review scope, lower risk of a broken-PR merge. Exception: when two TODOs act on the same file regions and the same reviewer mental model ("same reviewer context" test), batch them — INFRA-01+02 landed together correctly.

## Key Takeaways

- Most lessons are about NixOS being different from traditional Linux, not NixOS being wrong
- The biggest meta-lesson: compliance-as-code works, but only if you validate the code
- CI is not a gate; it is a tight feedback loop. Plan for iteration.
- Start with [[../shared-controls/shared-controls-overview]] — they satisfy the most frameworks per unit of effort
- Review [[../shared-controls/canonical-config]] before writing any Nix — it prevents the duplication problem
