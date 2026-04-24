# NixOS Gotchas

Critical pitfalls discovered during the [[review-findings/master-review|master review]] that will break compliance implementations.

## 1. Nix Store is World-Readable

`/nix/store` has `0444` files and `0555` directories. Any data in a store path is accessible to every user and process. Store paths persist until garbage collected, and underlying blocks are NOT securely wiped.

**Common leakage vectors:**
- Secrets embedded in Nix expressions
- `pkgs.writeText` or `builtins.toFile` with secret content
- Config files that interpolate secrets
- Scripts with hardcoded secrets in `ExecStart`

**Fix:** Use [[../shared-controls/secrets-management|sops-nix]] (project decision — not agenix). Never reference secrets directly in Nix expressions. Secrets go to `/run/secrets/` (tmpfs).

## 2. NixOS Paths Are Different

`/usr/bin`, `/usr/sbin`, `/sbin` don't exist on NixOS. All binaries live in `/nix/store` and are exposed via `/run/current-system/sw/bin/`.

**Impact:** Audit rules monitoring `/usr/bin/sudo` or `/usr/sbin/useradd` **monitor nothing**. AIDE rules for traditional paths produce noise.

**Fix:** Monitor `/run/current-system/sw/bin`, `/etc`, `/boot`, NOT traditional Linux paths.

## 3. nftables is the Default

NixOS 24.11+ defaults to nftables as the firewall backend. Using `networking.firewall.extraCommands` with iptables syntax **may silently fail**.

**Fix:** Use `networking.nftables.ruleset` or `networking.firewall` (which generates nftables internally). Never mix iptables and nftables.

## 4. Deprecated SSH Options Break sshd

- `Protocol 2` — removed from OpenSSH 7.6+. Setting it causes sshd to **fail to start**
- `ChallengeResponseAuthentication` — deprecated alias for `KbdInteractiveAuthentication` in OpenSSH 8.7+. Setting both creates conflicts

## 5. CUDA Breaks MemoryDenyWriteExecute

CUDA's JIT compiler requires W+X memory. Setting `MemoryDenyWriteExecute=true` on Ollama or any CUDA service **crashes GPU inference at runtime**. See [[ai-security/ai-security-residual-risks]].

## 6. Ollama Doesn't Support sd_notify

Using `WatchdogSec` or `Type=notify` with Ollama causes systemd to kill the service after the watchdog timeout. Use timer-based health checks instead.

## 7. Ollama Stores Models as Blobs

Models are content-addressed blobs in `/var/lib/ollama/models/blobs/sha256-<hex>`, NOT `.bin` files. Scripts using `find -name "*.bin"` find nothing. Manifests are in `/var/lib/ollama/models/manifests/`.

## 8. Phantom NixOS Options

`security.protectKernelImage = true` doesn't exist in NixOS. Using phantom options causes eval failures. Always verify options against `man configuration.nix`.

## 9. Flake Lock Staleness

NixOS is rolling + locked flake = pinned at a point in time. If `flake.lock` isn't updated regularly, packages accumulate unpatched CVEs. But updating may introduce regressions. Need a defined update cadence with [[shared-controls/vulnerability-management|vulnix scanning]].

## 10. statix Flags Empty Patterns

`statix check` rule `pattern-empty` fails on `{ ... }:` when no args are consumed — it wants `_:`. This conflicts with the "forward-compatible stub" convention of keeping `{ ... }:` so future edits can add `config`, `lib`, `pkgs` without diff noise on the pattern line.

**Fix:** use `_:` in [[../architecture/flake-skeleton-pattern#module-stubs-as-safe-no-ops|module stubs]]. Add `{ lib, ... }:` only when a real reference lands. The diff cost is one line — statix wins because it runs on every PR.

## 11. deadnix Flags Unused `self`

`deadnix --fail .` treats every unread binder as dead code, including `self` in `outputs = { self, nixpkgs, ... }:`. For a skeleton flake with no `checks.*` that reads `self`, remove it.

**Fix:** `outputs = { nixpkgs, ... }:` until a real `self` reference is added.

## 12. Handcrafting `flake.lock` Without a Nix CLI

If the implementation environment has no `nix` binary, a committed `flake.lock` cannot be produced because `narHash` values are *computed*, not declared. Three options:

| Option | Verdict |
|---|---|
| Hand-craft | Rejected — `narHash` requires an evaluator. |
| No lock; CI generates on first run | Accepted for skeleton bootstrap. |
| CI uploads lock as artifact + opens follow-up PR | Overkill for one-shot bootstrap; consider for recurring lock rotation. |

Skeleton ships without a lock; CI's first green run produces one; commit it back in a follow-up and delete the conditional bootstrap step in [[../architecture/ci-gate]].

## 13. FlakeHub-Coupled GitHub Actions

`DeterminateSystems/magic-nix-cache-action` now fails with `Unable to authenticate to FlakeHub` — the hosted cache has been folded into the FlakeHub product line. Any DeterminateSystems-hosted action must be audited for the same coupling before adoption.

**Fix:** prefer `cachix/install-nix-action@v27` for installation and `nix-community/cache-nix-action@v6` for caching. See [[github-actions-nix-stack]] for the full stack rationale.

## Key Takeaways

- Test every Nix snippet against real NixOS 24.11+ evaluation before committing
- The [[review-findings/master-review|master review]] found 17+ broken code issues across all modules
- Most gotchas are NixOS being different from traditional Linux, not NixOS being wrong
- Secrets management is the #1 operational risk — sops-nix is non-negotiable (agenix rejected; see [[../shared-controls/secrets-management]])
- Linter rules (`statix`, `deadnix`) beat prose conventions because they run on every PR
- DeterminateSystems-hosted CI actions now require FlakeHub auth — audit before adopting
