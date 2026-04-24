# Flake Skeleton Pattern

How to scaffold a NixOS flake that `nix eval` can validate end-to-end without real hardware. Used as the foundation for this project's [[flake-modules|six-module layout]] and gated by [[ci-gate]] on every PR.

## The Goal

Stand up `flake.nix`, a host directory, and one module directory per concern so that:

- `nix flake check` succeeds with no real configuration.
- `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath` returns a derivation path without realising anything.
- CI runs both on a stock runner with no disks, no hardware profile, no deploy target.

Deferring real configuration to later PRs keeps the initial scaffold reviewable and the CI gate in place before broken snippets can accumulate.

## Minimum Viable Options

`nixosSystem { ... }` refuses to evaluate without a handful of grounded values. The skeleton sets each to a placeholder:

| Option | Skeleton value | Why |
|---|---|---|
| `system.stateVersion` | `"24.11"` | Silences the missing-stateVersion warning; some modules read it. |
| `networking.hostName` | `"ai-server"` | Referenced transitively by multiple modules. |
| `fileSystems."/"` | `{ device = "/dev/disk/by-label/nixos"; fsType = "ext4"; }` | Any device string works as long as evaluation doesn't mount. |
| `boot.loader.systemd-boot.enable` | `true` via `lib.mkDefault` | Cheapest bootloader choice. See [[nix-implementation-patterns]]. |
| `boot.loader.efi.canTouchEfiVariables` | `true` via `lib.mkDefault` | Paired with systemd-boot. |
| `nixpkgs.hostPlatform` | `"x86_64-linux"` via `lib.mkDefault` | Avoids per-module platform inference. |

No `--eval-only` or `allowTest = true` escape hatch exists — the minimum set above is the cost of entry.

## Use `lib.mkDefault` on Everything Overridable

Wrapping every host-level scaffold value in `lib.mkDefault` lets ARCH-09 (Secure Boot via lanzaboote) and real deployment hardware modules override without module-system option-conflict errors. Without `mkDefault`, the next module that sets `boot.loader.*` or `nixpkgs.hostPlatform` at the same priority fails to evaluate.

## Module Stubs as Safe No-ops

Every module directory contains exactly one file — a stub that does nothing but carry an ownership comment:

```nix
_:
{
  # <module-name> — <one-line purpose>
  #
  # Control families: <list>
  # Implementation lives in <TODO IDs>.
}
```

The `_:` arg pattern is required by [[nixos-gotchas#10-statix-flags-empty-patterns|statix `pattern-empty`]] — `{ ... }:` fails CI when no args are consumed. Add `{ lib, ... }:` only when a real reference lands.

## `flake.lock` Bootstrap

If the implementation environment has no `nix` CLI, the skeleton can ship without a committed `flake.lock`. CI's first green run produces one; commit it in a follow-up and delete the conditional bootstrap step in [[ci-gate]]. Handcrafting `flake.lock` is not possible without a nix evaluator because `narHash` values are computed, not declared.

## Evaluate Without Realising

The canonical "does my config even parse" CI idiom is:

```
nix eval --raw --show-trace \
  .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath
```

`.drvPath` returns a string path — the evaluator walks the full module tree but the realiser is never invoked. This is what nixpkgs' own CI uses. `--show-trace` is essential for diagnosing the 17+ broken snippets catalogued in [[review-findings/master-review]]; without it, errors lose call-stack context.

## Key Takeaways

- Six options (`stateVersion`, `hostName`, `fileSystems."/"`, two `boot.loader` keys, `hostPlatform`) are the minimum for `nixosSystem` to evaluate on a runner with no hardware.
- Wrap host-level scaffold values in `lib.mkDefault` so future modules can override cleanly.
- Module stubs must use `_:` not `{ ... }:` to pass [[nixos-gotchas#10-statix-flags-empty-patterns|statix]].
- `nix eval .drvPath` is a full-tree parse without a build — the correct smoke test for [[ci-gate]].
- A missing `flake.lock` is recoverable: CI generates one on first run.
