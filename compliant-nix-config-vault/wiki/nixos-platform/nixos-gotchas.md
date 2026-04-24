# NixOS Gotchas

Critical pitfalls discovered during the [[../review-findings/master-review|master review]] that will break compliance implementations.

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

CUDA's JIT compiler requires W+X memory. Setting `MemoryDenyWriteExecute=true` on Ollama or any CUDA service **crashes GPU inference at runtime**. See [[../ai-security/ai-security-residual-risks]].

## 6. Ollama Doesn't Support sd_notify

Using `WatchdogSec` or `Type=notify` with Ollama causes systemd to kill the service after the watchdog timeout. Use timer-based health checks instead.

## 7. Ollama Stores Models as Blobs

Models are content-addressed blobs in `/var/lib/ollama/models/blobs/sha256-<hex>`, NOT `.bin` files. Scripts using `find -name "*.bin"` find nothing. Manifests are in `/var/lib/ollama/models/manifests/`.

## 8. Phantom NixOS Options

`security.protectKernelImage = true` doesn't exist in NixOS. Using phantom options causes eval failures. Always verify options against `man configuration.nix`.

## 9. Flake Lock Staleness

NixOS is rolling + locked flake = pinned at a point in time. If `flake.lock` isn't updated regularly, packages accumulate unpatched CVEs. But updating may introduce regressions. Need a defined update cadence with [[../shared-controls/shared-controls-overview|vulnix scanning]] (control 12 in the shared-controls overview).

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

## 14. Module System Forces All-or-Nothing for `options` vs `config`

A NixOS module can either:
- omit explicit `options` / `config` attrs and let every top-level attr be implicit config, OR
- declare `options.*` explicitly, in which case **every** config assignment must live under `config.*`.

Mixing the two — top-level `sops = { ... }` alongside `options.secrets.rotationDays = mkOption { ... }` — fails eval with `Module <path> has an unsupported attribute 'sops'. This is caused by introducing a top-level 'config' or 'options' attribute.`

**Fix:** the moment a module introduces `options.*`, wrap every other config assignment under `config = { ... };`. In the secrets module this means `config.sops = { ... }` rather than `sops = { ... }`.

## 15. Flake Inputs Tracking Mainline Break Silently

`github:Mic92/sops-nix` (no ref) resolves to the current master of sops-nix. On 2026-02-04 sops-nix master bumped `sops-install-secrets` to `buildGo125Module` and explicitly removed compatibility with NixOS 24.11 and 25.05. A flake that was green on Friday failed on Monday with `Function called without required argument "buildGo125Module"`.

**Fix:** never `url = "github:owner/repo"` without a rev for a flake input that gates the build. Pin to a commit SHA — the authoritative pin lives in `flake.lock` under the `sops-nix` input rev; consult that rather than a SHA embedded in prose that will go stale. Bump deliberately, not implicitly.

**Follow-up rule:** when adopting a new flake input, grep its default branch for upcoming breaking changes (search the repo's commit history for `buildGo<N>Module`, dropped-compat notices, or explicit "bump to <new-nixpkgs>" commits) before pinning without a rev.

## 16. `environment.etc."login.defs"` Overrides Conflict With Shadow Package

NixOS's shadow package writes `/etc/login.defs` itself. Any `environment.etc."login.defs".text = ''...''` or `environment.etc."login.defs" = { source = ...; }` override fights that write — some fields silently get dropped, some PAM modules read the unintended value, and `lib.mkForce` produces a file that lacks the defaults the shadow package normally supplies.

**Fix:** use the structured `security.loginDefs.settings.*` attrset (NixOS 24.11+). It merges cleanly with shadow-package defaults:

```nix
security.loginDefs.settings = {
  PASS_MAX_DAYS = 60;
  PASS_MIN_DAYS = 1;
  PASS_MIN_LEN = 15;
  UMASK = "077";
  ENCRYPT_METHOD = "SHA512";
};
```

Note the types: integers drop the quotes, strings keep them. `SHA_CRYPT_ROUNDS` is split into `SHA_CRYPT_MIN_ROUNDS` + `SHA_CRYPT_MAX_ROUNDS`.

## 17. `users.mutableUsers = false` Fails Eval Without a Wheel User Login

NixOS asserts that if `users.mutableUsers = false`, at least one of the following must be true: root has a password, some wheel user has a password, or some wheel user has `openssh.authorizedKeys.keys` declared. Otherwise eval fails with `Failed assertions: - Neither the root account nor any wheel user has a password or SSH authorized key`.

The assertion is correct — it prevents a classic lock-out on a real deployment.

**Current approach (ARCH-11 onward).** The `modules/accounts/` module declares the admin user with `openssh.authorizedKeys.keys` in the host; that satisfies the assertion structurally. No escape hatch is needed. See [[../shared-controls/account-lifecycle]] for the module surface.

**Historical note — do not copy.** Before ARCH-11, the skeleton used

```nix
users.allowNoPasswordLogin = lib.mkDefault true;
```

inside `stig-baseline` to pass CI without an admin user declared, with each deployment overriding back to `lib.mkForce false` once it declared its own user. That escape hatch was retired in PR #49. A lingering `users.allowNoPasswordLogin = true` on current main would be a regression.

## 18. `boot.tmp.useTmpfs = true` Omits `noexec`

NixOS's helper `boot.tmp.useTmpfs = true` mounts `/tmp` as tmpfs with `nosuid,nodev` but NOT `noexec`. STIG wants all three. If you set the helper to true and also declare `fileSystems."/tmp"` explicitly, you get a module-system collision on the mount point.

**Fix:** drop the helper, declare `fileSystems."/tmp"` directly:

```nix
fileSystems."/tmp" = {
  device = "tmpfs";
  fsType = "tmpfs";
  options = [ "defaults" "size=50%" "mode=1777" "nosuid" "nodev" "noexec" ];
};
```

Own the options list; don't rely on the helper.

## Key Takeaways

- Test every Nix snippet against real NixOS 24.11+ evaluation before committing
- The [[../review-findings/master-review|master review]] found 17+ broken code issues across all modules
- Most gotchas are NixOS being different from traditional Linux, not NixOS being wrong
- Secrets management is the #1 operational risk — sops-nix is non-negotiable (agenix rejected; see [[../shared-controls/secrets-management]])
- Linter rules (`statix`, `deadnix`) beat prose conventions because they run on every PR
- DeterminateSystems-hosted CI actions now require FlakeHub auth — audit before adopting
- When a module uses `options.*`, every config assignment must live under `config.*` — no mixing
- Flake inputs without a rev track upstream mainline; pin to a SHA for any input that gates the build
- Structured options beat file-override `.text`/`.source` overrides — use `security.loginDefs.settings.*`, not `environment.etc."login.defs"`
- `users.mutableUsers = false` triggers a lock-out assertion; since ARCH-11 the [[../shared-controls/account-lifecycle|accounts module]] satisfies it structurally — the pre-ARCH-11 `users.allowNoPasswordLogin` escape hatch is retired
- `boot.tmp.useTmpfs = true` omits `noexec` — declare `fileSystems."/tmp"` explicitly if you need all three hardening flags
