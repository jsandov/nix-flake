# Boot Integrity

How the project handles UEFI Secure Boot — a feature that *requires* hardware-side key provisioning to function, but whose *configuration* has to ship with the flake. The tension: CI / skeleton deployments have no UEFI and no sbctl keys, yet the flake must evaluate. Solution: a dormant-vs-active mode gated behind `security.secureBoot.enable`.

## The Dormant / Active Split

```nix
options.security.secureBoot = {
  enable = lib.mkEnableOption "...";
  pkiBundle = lib.mkOption { type = types.str; default = "/var/lib/sbctl"; };
};

config = lib.mkMerge [
  { /* unconditional hardening */ }
  (lib.mkIf cfg.enable { /* lanzaboote block */ })
];
```

**Dormant** (`enable = false`, the default): host boots on systemd-boot. Lanzaboote module is imported but does nothing. Unconditional hardening (core dumps off, ctrlAltDel disabled, kernel blacklist applied, /tmp noexec, wireless off, mutableUsers off) applies regardless.

**Active** (`enable = true`): lanzaboote replaces systemd-boot. Host must have `/var/lib/sbctl` populated with a key enrolled in UEFI DB before first `nixos-rebuild switch` — otherwise the next boot fails Secure Boot verification.

## Operator Key-Provisioning Procedure

Deliberately out-of-band — keys live on-host, not in the repo:

1. Boot the host on systemd-boot with `security.secureBoot.enable = false` (dormant).
2. `sudo sbctl create-keys` generates the PKI bundle at `/var/lib/sbctl`.
3. Reboot into UEFI setup. Enroll the public key (`sbctl enroll-keys --microsoft` is usually the right form — it adds your key plus Microsoft's keys so Windows can still boot dual-boot systems).
4. Back in the running system, flip `security.secureBoot.enable = true` in the host config.
5. `nixos-rebuild switch`. The next boot uses lanzaboote with Secure Boot verification.

Running `sbctl enroll-keys` before having a key generated would fail. The strict order (keys → enroll → flip flag → rebuild) is non-obvious and worth documenting explicitly in the host config as well.

## `mkMerge` + `mkIf` Structural Pattern

The module uses `lib.mkMerge [ alwaysAppliesBlock (lib.mkIf cfg.enable gatedBlock) ]` rather than sprinkling `lib.mkIf` inside a single attrset. Why:

- Reader sees "always" vs "opt-in" as distinct visual blocks.
- Easier to reason about — the attribute sets are independent; a bug in one doesn't cascade.
- Easier to refactor — extracting the gated block into a separate module later is a structural move, not a surgical edit.

**Rule of thumb:** when a module has >2 lines of gated config, use `mkMerge + mkIf`. For a single gated key, `lib.mkIf` inline is fine.

## Priority Dance — `mkForce` vs `mkDefault`

The host module sets `boot.loader.systemd-boot.enable = lib.mkDefault true`. When `secureBoot.enable = true`, stig-baseline sets the same option to `lib.mkForce false` inside the gated block. `mkForce` beats `mkDefault`, so lanzaboote takes over cleanly. When `secureBoot.enable = false`, the gated block is inert and `mkDefault true` wins — systemd-boot runs normally.

This works because NixOS module priorities are: `mkOptionDefault` (100) < `mkDefault` (1000) < normal assignment (100 — same) < `mkOverride 50` = `mkForce` (50). Lower number = higher priority.

**Lesson:** always wrap "I want this to win over the host's default" assignments in `mkForce`. Don't rely on assignment order; module composition doesn't guarantee it.

## First Canonical-at-Scale Consumer

stig-baseline is the first module to read from `config.canonical.*` at scale — nine distinct values:

| Option | Source |
|---|---|
| `boot.loader.systemd-boot.editor` | `canonical.nixosOptions.systemdBootEditor` |
| `systemd.ctrlAltDelUnit` | `canonical.nixosOptions.ctrlAltDelUnit` |
| `systemd.coredump.extraConfig` | `canonical.nixosOptions.coredumpStorage` |
| `boot.kernel.sysctl."kernel.core_pattern"` | `canonical.nixosOptions.coredumpKernelPattern` |
| `boot.blacklistedKernelModules` | `canonical.kernelModuleBlacklist` |
| `networking.wireless.enable` | `canonical.nixosOptions.wirelessEnable` |
| `services.xserver.enable` | `canonical.nixosOptions.xserverEnable` |
| `users.mutableUsers` | `canonical.nixosOptions.usersMutableUsers` |
| `nix.settings.allowed-users` | `canonical.nixosOptions.nixAllowedUsers` |

Nine reads in one module validates the [[../shared-controls/canonical-config|ARCH-02 declare-once-consume-everywhere contract]] at scale. A change to any canonical value propagates to stig-baseline automatically on the next eval — no module edit needed. This is the payoff for the canonical investment.

## /tmp Hardening — Explicit Over `boot.tmp.useTmpfs`

NixOS offers `boot.tmp.useTmpfs = true` as a one-liner to mount /tmp as tmpfs. It does NOT add `noexec`. STIG wants noexec. Options:

1. Use the helper, accept nosuid+nodev.
2. Declare `fileSystems."/tmp"` explicitly with the options list you want.

Chose #2. Explicit entry:

```nix
fileSystems."/tmp" = {
  device = "tmpfs";
  fsType = "tmpfs";
  options = [ "defaults" "size=50%" "mode=1777" "nosuid" "nodev" "noexec" ];
};
```

Mixing `boot.tmp.useTmpfs = true` with an explicit `fileSystems."/tmp"` would collide — the helper generates its own `fileSystems` entry. Own one path; drop the other.

**/dev/shm and /var/tmp deliberately deferred:**

- `/dev/shm` default is `nosuid,nodev` without noexec. Many legitimate apps use /dev/shm for JIT-able buffers (browsers, Electron, some ML frameworks). Hardening to noexec would break them for a single-operator system that doesn't have the threat in scope.
- `/var/tmp` is typically persistent; tmpfs-mounting it would surprise operators.

Both are acknowledged partial-hardening points. Documented in this article and in the raw note rather than hidden.

## Emergency / Rescue Targets

NixOS's default emergency and rescue units already use `sulogin`, which requires the root password. STIG requires this; the default satisfies it. No explicit config added — a comment in the module documents the dependency so evidence review (future ARCH-10) can confirm the behaviour.

If a future NixOS change weakens the default, evidence review catches the gap. Documenting-not-forcing is the right trade-off: forcing would require overriding a built-in unit, fragile, and the default is already correct.

## Related Gotchas

- [[../nixos-platform/nixos-gotchas|#15]] — Flake inputs tracking mainline break silently. Lanzaboote is SHA-pinned, not `@main`.
- [[../nixos-platform/nixos-gotchas|#17]] — `users.mutableUsers = false` triggers a lockout assertion unless a wheel user has SSH keys or a root password is set. Skeleton needs `users.allowNoPasswordLogin = lib.mkDefault true` escape hatch.
- [[../nixos-platform/nixos-gotchas|#18]] — `boot.tmp.useTmpfs` omits noexec.

## Key Takeaways

- Gate Secure Boot behind `security.secureBoot.enable` so CI / skeleton deployments evaluate.
- Use `lib.mkMerge [ alwaysBlock (lib.mkIf cfg.enable gatedBlock) ]` when you have more than a few gated settings.
- `lib.mkForce` inside a gated block wins over host-level `lib.mkDefault`; don't rely on assignment order.
- stig-baseline is the canonical-module's first scale consumer — nine distinct reads from `config.canonical.*`.
- Explicit `fileSystems."/tmp"` beats `boot.tmp.useTmpfs` when you need noexec.
- `/dev/shm` and `/var/tmp` deliberately left at NixOS defaults — the trade-off is real and documented.
- Pin flake inputs by commit SHA (gotcha #15).
