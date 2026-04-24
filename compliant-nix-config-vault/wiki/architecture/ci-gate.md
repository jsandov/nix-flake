# CI Gate

The CI contract that catches broken Nix before it merges. Pairs with [[flake-skeleton-pattern]] to make the "every PRD snippet must evaluate" acceptance criterion enforceable rather than aspirational.

## Why a Gate is Mandatory

The [[review-findings/master-review]] catalogued 17+ broken Nix snippets in the PRDs — phantom `security.protectKernelImage`, deprecated `Protocol 2`, iptables rules with mutually-exclusive DROPs, audit rules pointing at paths that do not exist on NixOS. Without a gate, every framework module PR would compound unvalidated errors. The gate runs on every PR and on every push to `main`.

## What the Gate Runs

Every PR triggers `.github/workflows/nix-check.yml`:

1. **`nix flake check --show-trace --no-build`** — evaluates all flake outputs, runs `checks.*`.
2. **`nix eval --raw .#nixosConfigurations.ai-server.config.system.build.toplevel.drvPath`** — walks the entire module tree end-to-end without realising. This is the primary smoke test (see [[flake-skeleton-pattern#evaluate-without-realising]]).
3. **`statix check .`** — anti-pattern lint (empty patterns, dead bindings, redundant parentheses).
4. **`deadnix --fail .`** — unused-binding detector.
5. **Legacy-FHS-path lint** — `grep -rnE '/(usr/bin|usr/sbin|sbin)/' modules/ hosts/` exits 1 on any hit. Catches [[nixos-gotchas#2-nixos-paths-are-different|the NixOS path gotcha]] before it lands.

## Stack Choices

See [[nixos-platform/github-actions-nix-stack]] for the installer + cache + lint stack selected, the supply-chain caveats, and the reasons the DeterminateSystems hosted pieces were rejected.

## Iterative Discovery

CI bring-up for a NixOS flake is a sequence of reveals, not a single validation. The first four live runs on the ARCH-01 + ARCH-03 PR surfaced, in order:

1. `DeterminateSystems/magic-nix-cache-action` requiring FlakeHub auth — hosted-cache supply-chain drift.
2. `checks.<system>.eval = drvPath` rejected because `checks.*` must be real derivations, not strings.
3. `statix` flagging `{ ... }:` module stubs as `pattern-empty`.
4. `deadnix` flagging an unused `self` binder in `outputs`.

Each pass unlocks the next layer. **Budget ≥3 CI iterations for any non-trivial module PR.** The iteration sequence is captured in the raw research notes for future reference.

## Meta-Lesson

A strict lint beats a human convention every time, because the lint survives the humans. [[review-findings/lessons-learned]] frames this as the broader ARCH-16 boundary-lints principle: any time the PRD prose and the linter disagree, the linter wins because it runs on every PR.

## Known Caveats

- **flake.lock** is bootstrapped by the workflow on first run if absent. Once committed, the conditional bootstrap step in the workflow should be deleted so the pinned lock is the reproducibility contract.
- **Action pins** ship at `@vN` for the skeleton PR. Rotate to commit SHAs once the first green run stabilises, and enable Dependabot for the `github-actions` ecosystem.
- **Cache layer** is intentionally absent on the skeleton. Skeleton eval is fast enough not to need it. When caching becomes necessary, prefer `nix-community/cache-nix-action` over any hosted substituter.

## Key Takeaways

- The gate is the enforcement mechanism for the "every snippet evaluates" acceptance criterion — without it, the master-review findings would re-accumulate.
- Five checks: `nix flake check`, `nix eval` toplevel, `statix`, `deadnix`, legacy-FHS grep.
- `nix eval .drvPath` is the primary smoke test — full-tree parse, no build.
- Each new CI pass tends to surface one more hidden issue; plan for ≥3 iterations on any real module PR.
- Lints win over prose conventions because they run on every commit.
