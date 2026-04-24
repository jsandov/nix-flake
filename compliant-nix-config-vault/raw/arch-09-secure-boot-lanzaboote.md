# ARCH-09 — Secure Boot via lanzaboote

Session notes from adding UEFI Secure Boot support and making `modules/stig-baseline/default.nix` real. Second non-stub module, first module with a gated feature.

## Why this one is structurally interesting

Most NixOS modules enable a thing unconditionally. Secure Boot is different: a real `boot.lanzaboote.enable = true` requires `/var/lib/sbctl` to be populated with a key enrolled in UEFI DB *before* first boot. CI has no UEFI, no sbctl, no real disk — evaluation-only. So the module ships the configuration *shape* unconditionally (canonical-driven core dumps, ctrlAltDel disable, kernel blacklist, /tmp hardening) but gates lanzaboote itself behind `security.secureBoot.enable` which defaults to false.

A real deployment:

1. Boots the server on systemd-boot (lanzaboote dormant).
2. Runs `sudo sbctl create-keys` then `sudo sbctl enroll-keys --microsoft`.
3. Flips `security.secureBoot.enable = true` in the host config.
4. `nixos-rebuild switch` replaces systemd-boot with lanzaboote and signs the next-boot kernel.

Skeleton / CI / test environments never flip the flag.

## Flake input

```nix
lanzaboote = {
  url = "github:nix-community/lanzaboote/4eda91dd5abd2157a2c7bfb33142fc64da668b0a";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Pinned by commit SHA (2026-04-21). Following [[../nixos-platform/nixos-gotchas|gotcha #15]] — never `@main` for an input that gates the build. `inputs.nixpkgs.follows = "nixpkgs"` keeps the dependency graph clean (don't drag in a second nixpkgs pin).

## Module shape: `mkMerge` + `mkIf`

```nix
config = lib.mkMerge [
  { /* unconditional hardening */ }
  (lib.mkIf cfg.enable { /* lanzaboote */ })
];
```

The unconditional attrset applies whether Secure Boot is on or off — canonical core-dump suppression, ctrlAltDel disable, kernel blacklist, /tmp hardening, etc. are valuable regardless. The gated block only activates when the operator opts in.

Why `mkMerge` rather than a single attrset with `lib.mkIf` sprinkled inside: keeps the two concerns visually separate in source. Reader sees "always applies" vs "opt-in" as distinct blocks, not intermixed per-key.

## Canonical consumption

Every value that has a canonical answer reads from `config.canonical.*`:

| Setting | Source |
|---|---|
| `boot.loader.systemd-boot.editor` | `canonical.nixosOptions.systemdBootEditor` |
| `systemd.ctrlAltDelUnit` | `canonical.nixosOptions.ctrlAltDelUnit` |
| `systemd.coredump.extraConfig` (`Storage=...`) | `canonical.nixosOptions.coredumpStorage` |
| `boot.kernel.sysctl."kernel.core_pattern"` | `canonical.nixosOptions.coredumpKernelPattern` |
| `boot.blacklistedKernelModules` | `canonical.kernelModuleBlacklist` |
| `networking.wireless.enable` | `canonical.nixosOptions.wirelessEnable` |
| `services.xserver.enable` | `canonical.nixosOptions.xserverEnable` |
| `users.mutableUsers` | `canonical.nixosOptions.usersMutableUsers` |
| `nix.settings.allowed-users` | `canonical.nixosOptions.nixAllowedUsers` |

Nine distinct consumer uses — the first module to exercise the canonical contract at scale. Validates the ARCH-02 design: downstream modules read without duplicating the value narrative.

## /tmp hardening — explicit, not `boot.tmp.useTmpfs`

NixOS has a helper `boot.tmp.useTmpfs = true` that auto-generates a tmpfs mount for `/tmp`. It does NOT add `noexec`. Two paths:

1. Use `boot.tmp.useTmpfs = true` and accept nosuid+nodev.
2. Declare `fileSystems."/tmp"` explicitly and own the options list.

Chose #2 because STIG wants noexec. Explicit fileSystems entry with `options = [ "defaults" "size=50%" "mode=1777" "nosuid" "nodev" "noexec" ]`.

### /dev/shm and /var/tmp deliberately deferred

`/dev/shm` is typically managed by util-linux defaults (nosuid,nodev). Extending to `noexec` via a remount unit would break apps that use /dev/shm for JIT-able buffers — browsers, Electron, some ML frameworks. The threat model's adversary list doesn't include "attacker executing from /dev/shm after gaining arbitrary write"; not a blocker.

`/var/tmp` is typically persistent, so tmpfs-mounting it would surprise future operators. Skipped.

Both are acknowledged partial-hardening points. An STIG assessor reading the evidence will see the gap documented rather than hidden.

## The `security.secureBoot` options block

Two options:

- `enable` via `lib.mkEnableOption` — standard NixOS pattern. Default off.
- `pkiBundle` via `mkOption { type = types.str; default = "/var/lib/sbctl"; }` — overridable if an operator uses a non-default sbctl path.

Reads from `config.security.secureBoot.enable` via `cfg = config.security.secureBoot;` for concise `cfg.enable` / `cfg.pkiBundle` references.

## Emergency / rescue targets

NixOS's default emergency / rescue units already use `sulogin`, which requires the root password (or empty-password-rejection). STIG requires this; the default satisfies it. No explicit config added — a comment in the module documents the dependency so evidence generation (ARCH-10 future) can confirm the behaviour.

If a future NixOS change weakens the default, evidence review catches the gap. Documenting-not-forcing is the right trade-off: forcing would require overriding a built-in NixOS unit, fragile, and the default is already correct.

## Relationship to hosts/ai-server/default.nix

The host module sets `boot.loader.systemd-boot.enable = lib.mkDefault true`. When `security.secureBoot.enable = false` (skeleton default), that wins and systemd-boot drives the boot flow. When the operator flips to `true`, stig-baseline's `lib.mkForce false` wins (mkForce > mkDefault) and lanzaboote replaces systemd-boot. Clean override; no host edit needed.

## Gotchas encountered

- **`boot.tmp.useTmpfs` collides with explicit `fileSystems."/tmp"`** — NixOS generates a fileSystems entry from the helper. Drop the helper entirely when you need custom options.
- **`lanzaboote.nixosModules.lanzaboote`** has to be imported in the flake's modules list for the options to exist. Missing that produces `option boot.lanzaboote.enable does not exist`.
- **`lib.mkForce false` on `systemd-boot.enable`** is the correct priority dance — hosts can set `mkDefault true` and still be overridden by stig-baseline without the module system raising a priority-conflict error.

## Suggested wiki compile targets

- `wiki/architecture/boot-integrity.md` (new) — the two-mode module pattern (dormant on skeleton / active on deployment), the operator key-provisioning procedure, the mkMerge+mkIf structural choice, the /tmp hardening explicit vs boot.tmp.useTmpfs decision.
- Extend `wiki/nixos-platform/nixos-gotchas.md` with an entry on `boot.tmp.useTmpfs` vs explicit fileSystems.
- Extend `wiki/shared-controls/canonical-config.md` with a "first consumer at scale" callout referencing stig-baseline's nine-canonical-reads.
