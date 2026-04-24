# GitHub Actions + Nix Stack

Action choices for running `nix flake check` and `nix eval` on GitHub-hosted runners, with the supply-chain caveats learned during CI bring-up. Consumed by [[../architecture/ci-gate]].

## Recommended Stack (2026)

| Concern | Action | Rationale |
|---|---|---|
| Nix install | `cachix/install-nix-action@v27` | Stable, no hosted-cache coupling. |
| Cache | *(none for skeleton)* | See "Cache caveat" below. |
| Lint | `nix run nixpkgs#statix` and `nix run nixpkgs#deadnix --fail` | Linter versions pin to the project's own `nixpkgs` input. No extra action supply chain. |
| Runner | `ubuntu-24.04` (pinned) | `ubuntu-latest` rolls silently. |
| Permissions | `contents: read` | No writes, no package publishes. |
| Concurrency | `cancel-in-progress: true` keyed on workflow + ref | Saves minutes on rapid pushes. |

## Cache Caveat — Avoid FlakeHub-Coupled Actions

`DeterminateSystems/magic-nix-cache-action` was the zero-config recommendation through 2024 but now fails CI with `Unable to authenticate to FlakeHub. Individuals must register at FlakeHub.com.` The hosted cache has collapsed into the FlakeHub-gated product line. Any action under `DeterminateSystems/*` should be audited for the same coupling before adoption.

**Alternatives when caching becomes necessary:**

- `nix-community/cache-nix-action@v6` — transparent wrapper around `actions/cache`. More cache-key tuning required, but no hosted dependency.
- `cachix/cachix-action@v15` — only if a public binary cache is in scope. Adds `CACHIX_AUTH_TOKEN` secret management.

For the project skeleton, the eval is fast enough that no cache is needed. Defer the caching decision until module content begins driving eval cost.

## Installer Choice — `cachix/install-nix-action` over Determinate

`DeterminateSystems/nix-installer-action` installs faster and enables flakes by default, but ships `accept-flake-config = true` by default and logs pull-request-scoped telemetry. `cachix/install-nix-action@v27` is slower by ~10 seconds on a cold runner but has no phone-home surface and composes cleanly with `accept-flake-config = false`. For a compliance project, the slower, quieter installer is the better pick.

If the installer is later rotated back to Determinate, set `diagnostic-endpoint: ""` and `determinate: false` and audit every release for new defaults.

## Dry-Eval Idiom

```yaml
- name: Evaluate ai-server toplevel (no realisation)
  run: |
    nix eval --raw --show-trace \
      .#nixosConfigurations.ai-server.config.system.build.toplevel.drvPath
```

`.drvPath` is a string — the evaluator walks the full module tree but no derivation is realised. See [[../architecture/flake-skeleton-pattern#evaluate-without-realising]] for why this is the canonical smoke test.

## Performance Expectations

| Scenario | Wall clock |
|---|---|
| Cold `nix flake check` on a moderate NixOS config, no cache | 3–8 min |
| `nix eval` toplevel `drvPath` alone | 5–15 s |
| `statix` + `deadnix` combined | 10–20 s |
| Whole workflow, warm | 1–2 min |

Free-tier GitHub Actions limits (2000 minutes/month private, unlimited public) are not a blocker for this project's expected PR volume.

## Supply-Chain Hardening Checklist

- [ ] Rotate all third-party actions from `@vN` tags to commit SHAs.
- [ ] Enable Dependabot for the `github-actions` ecosystem.
- [ ] Commit `flake.lock` and delete the conditional "bootstrap if missing" step.
- [ ] Pin `nixpkgs` by commit SHA in `flake.nix` as an additional belt-and-braces.
- [ ] Audit every new DeterminateSystems release for added FlakeHub coupling before adopting.

## Alternatives Briefly Considered

- **Garnix** — managed Nix-native CI, zero-config cache. Worth revisiting if GitHub Actions cache churn becomes a pain point. Private infrastructure dependency is the tradeoff.
- **Hercules-CI** — mature, paid, org-scale. Overkill for a single-repo project.
- **flake.parts** — composition helpers for `checks.*`, orthogonal to CI runner choice. Useful later; not needed for the skeleton.

## Key Takeaways

- Default installer: `cachix/install-nix-action@v27` — slower than Determinate, no phone-home.
- Default cache: **none** for the skeleton; `nix-community/cache-nix-action` when cost justifies it.
- **Never** trust a DeterminateSystems hosted action without auditing for FlakeHub coupling first.
- Action pins at `@vN` are a starting point; rotate to SHAs + Dependabot before the first module PR lands.
- `nix eval .drvPath` is the canonical dry-eval; no hardware, no realisation.
