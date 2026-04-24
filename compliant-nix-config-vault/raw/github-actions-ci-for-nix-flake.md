# GitHub Actions CI for a nix flake with a NixOS configuration

Research notes gathered for ARCH-03 (CI gate that runs `nix flake check` and `nix eval` on every PR). Captures the decision rationale behind `.github/workflows/nix-check.yml` so it can be distilled into a wiki article on a future compile pass.

## Research-environment caveat

The research agent that gathered these findings had `WebFetch` and `WebSearch` disabled. Every claim below is grounded in model training data (cutoff January 2026) and must be re-verified against current upstream before merging action pins to `main`. Items with `[verify]` are especially susceptible to drift.

## Verdict

Yes. GitHub Actions can reliably run `nix flake check` and `nix eval .#nixosConfigurations.ai-server.config.system.build.toplevel.drvPath`. Evaluation-only passes are cheap — typical cold-cache run is 3–8 min; warm is 30–90 s. Free-tier runner budget is not a blocker for the nix-flake project's expected PR volume.

## Recommended stack

### Installer — `DeterminateSystems/nix-installer-action`

Faster install (~5 s versus ~15 s for `cachix/install-nix-action`), flakes and `nix-command` on by default, actively maintained. Superseded `cachix/install-nix-action` as the community default through 2024–2025. `[verify: latest release tag]`

Rejected alternative: `cachix/install-nix-action` still works but is no longer the default recommendation in most flake-CI examples.

### Cache — `DeterminateSystems/magic-nix-cache-action`

Zero-config. No auth token. Backs the Nix store by the GitHub Actions cache service, scoped per-repo. No private infrastructure needed.

Rejected alternatives:

- `nix-community/cache-nix-action@v6` — transparent mechanism (wraps `actions/cache`), useful fallback if magic-nix-cache has closure-size issues. More cache-key tuning required.
- `cachix/cachix-action` — needed only when a public binary cache is in scope for downstream consumers. Adds `CACHIX_AUTH_TOKEN` secret management overhead.

`[verify: DeterminateSystems has announced no deprecation of magic-nix-cache as of mid-2025]`

### Linters — `statix` + `deadnix` via `nix run nixpkgs#<tool>`

Running via `nix run` keeps the linters' versions pinned to the project's own `nixpkgs` input. No third-party action supply chain. First run pays the fetch; subsequent runs hit the magic cache.

Rejected: `reckenrode/nix-build-check-action` exists but adds unnecessary action-layer risk for marginal UX gain.

## Evaluating a NixOS configuration without realising it

The idiom:

```
nix eval --raw --show-trace \
  .#nixosConfigurations.ai-server.config.system.build.toplevel.drvPath
```

- `.drvPath` returns the path to the derivation as a string. The evaluator walks the full module tree — catching every typo, missing option, bad assertion — but the realiser is never invoked.
- `--raw` prevents quoting so the output is copy-paste-friendly in error logs.
- `--show-trace` is essential for diagnosing the ~17 broken snippets flagged in MASTER-REVIEW Systemic Issue #2; without it, errors lose call-stack context.

This is the canonical "does my NixOS config even evaluate" smoke test for CI. nixpkgs's own CI uses the same pattern.

## Minimum runner configuration

| Concern | Choice | Rationale |
|---|---|---|
| Runner OS | `ubuntu-24.04` (pinned) | `ubuntu-latest` silently rolls forward; pin for reproducibility. |
| Permissions | `contents: read` | Workflow never writes to the repo or pushes packages. |
| Concurrency | `cancel-in-progress: true`, keyed on workflow + ref | Saves runner minutes on rapid-fire pushes. |
| Timeout | `timeout-minutes: 30` | Cold runs should fit in 10 min; 30 is safety margin. |

## Cross-architecture matrix strategy

Native ARM runners (`ubuntu-24.04-arm`) are GA on GitHub as of 2025 `[verify]`. A matrix entry would double runtime minutes. Recommendation: defer until there is a concrete `aarch64-linux` deployment target. If added later:

```yaml
strategy:
  matrix:
    runner:
      - ubuntu-24.04
      - ubuntu-24.04-arm
runs-on: ${{ matrix.runner }}
```

QEMU cross-architecture emulation is ~10× slower — not recommended for routine CI.

## Cost / performance benchmarks (rough)

| Scenario | Wall clock |
|---|---|
| Cold `nix flake check` on a moderate NixOS config, no cache | 3–8 min |
| Warm (magic-nix-cache hit) | 30–90 s |
| `nix eval` toplevel `drvPath` alone (warm) | 5–15 s |
| `statix` + `deadnix` combined (warm) | 10–20 s |

Free-tier limits: 2000 minutes/month private, unlimited public. Not a concern for this project.

## Supply-chain hardening

Action pins in the skeleton workflow use `@main` because the research environment could not verify latest SHAs. Follow-up once the first green run lands:

1. Rotate every third-party action from `@main`/`@vN` to a full commit SHA.
2. Add Dependabot for the `github-actions` ecosystem — it will open PRs for new SHAs with release notes.
3. Consider pinning `nixpkgs` by SHA in `flake.nix` or committing `flake.lock` so the evaluator is byte-for-byte reproducible across PRs.

## Open decisions

- **Commit `flake.lock` from day one?** Recommended yes. Today the skeleton omits it because this environment has no `nix` CLI. CI's first green run produces one; commit it in a follow-up and delete the "lock if missing" step.
- **Public Cachix now or later?** Later. Magic-nix-cache covers internal CI reruns; a public cache only matters when external consumers install from this flake.
- **arm64 matrix now or later?** Later, as above.
- **Garnix / Hercules-CI / flake.parts alternatives?** Garnix (managed Nix-native CI, zero-config cache) is the closest competitor and worth revisiting if GitHub Actions cache churn becomes a pain point. Hercules-CI is paid and org-scale. flake.parts is orthogonal — a composition helper for `checks`, not a runner.

## Evidence (canonical landing pages; individual versions to be re-verified)

- `DeterminateSystems/nix-installer-action` — https://github.com/DeterminateSystems/nix-installer-action
- `DeterminateSystems/magic-nix-cache-action` — https://github.com/DeterminateSystems/magic-nix-cache-action
- `cachix/install-nix-action` — https://github.com/cachix/install-nix-action
- `cachix/cachix-action` — https://github.com/cachix/cachix-action
- `nix-community/cache-nix-action` — https://github.com/nix-community/cache-nix-action
- `nerdypepper/statix` — https://github.com/nerdypepper/statix
- `astro/deadnix` — https://github.com/astro/deadnix
- NixOS manual — writing NixOS modules — https://nixos.org/manual/nixos/stable/#sec-writing-nixos-modules
- nixpkgs CI (prior art for `.drvPath` idiom) — https://github.com/NixOS/nixpkgs/tree/master/.github/workflows
- Garnix — https://garnix.io
- Hercules-CI — https://hercules-ci.com
- flake.parts — https://flake.parts

## Suggested wiki compile targets

If these notes are distilled into wiki articles:

- `wiki/architecture/ci-gate.md` — the evaluate-not-realise idiom, why it works, what it catches.
- `wiki/nixos-platform/github-actions-nix-stack.md` — installer + cache + linter choices, 2025/2026 state of the art, supply-chain hardening checklist.
- `wiki/shared-controls/ci-as-control.md` — CI evaluation as evidence for NIST CM-6 (configuration settings), SI-2 (flaw remediation), and the PRD's "every Nix snippet must evaluate" acceptance criterion.
