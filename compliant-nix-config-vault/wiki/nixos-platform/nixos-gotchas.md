# NixOS Gotchas

Critical pitfalls discovered during the [[review-findings/master-review|master review]] that will break compliance implementations.

## 1. Nix Store is World-Readable

`/nix/store` has `0444` files and `0555` directories. Any data in a store path is accessible to every user and process. Store paths persist until garbage collected, and underlying blocks are NOT securely wiped.

**Common leakage vectors:**
- Secrets embedded in Nix expressions
- `pkgs.writeText` or `builtins.toFile` with secret content
- Config files that interpolate secrets
- Scripts with hardcoded secrets in `ExecStart`

**Fix:** Always use sops-nix or agenix. Never reference secrets directly in Nix expressions. Secrets go to `/run/secrets/` (tmpfs).

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

## Key Takeaways

- Test every Nix snippet against real NixOS 24.11+ evaluation before committing
- The [[review-findings/master-review|master review]] found 17+ broken code issues across all modules
- Most gotchas are NixOS being different from traditional Linux, not NixOS being wrong
- Secrets management is the #1 operational risk — sops-nix/agenix is non-negotiable
