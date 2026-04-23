# NixOS Compliance Advantages

Six structural properties that make NixOS uniquely strong for compliance.

## 1. Declarative State (CM-2, CM-6)

The entire system configuration is code. No configuration drift from imperative changes. Every service, port, user, and firewall rule is visible in the flake. `nixos-rebuild switch` applies the declared state atomically.

## 2. Immutable Store (SI-3, SI-7, SR-9, SR-11)

`/nix/store` is read-only and content-addressed. Every path is derived from the cryptographic hash of all its inputs. `nix store verify --all` is **strictly stronger** than signature-based AV for detecting tampering — it detects ANY modification, not just known signatures.

## 3. Atomic Upgrades and Rollback (CP-10, SI-2, CM-3)

Updates are atomic — no partially-updated state. Previous generations retained at boot. `nixos-rebuild switch --rollback` provides instant recovery. Supports both [[shared-controls/incident-response-hooks|incident response]] and change management.

## 4. Reproducible Builds (CM-2, SA-10)

Same flake inputs → identical system on different hardware. `flake.lock` records exact commit hash and NAR hash for all inputs. Supports disaster recovery and evidence consistency.

## 5. No User-Installed Software (CM-11, CM-7)

`users.mutableUsers = false` means only declared accounts exist. `nix.settings.allowed-users` restricts who can use the Nix CLI. No `apt install` equivalent for unauthorized users.

## 6. Garbage Collection (MP-6, SR-12)

`nix-collect-garbage -d` deterministically removes all unreferenced store paths. Supports secure decommissioning of old software.

## Evidence Generation

| Evidence | Method |
|---|---|
| System config snapshot | `nixos-rebuild dry-build` + Git hash |
| User inventory | `nix eval .#config.users.users --json` |
| Port inventory | `nix eval .#config.networking.firewall --json` |
| Package BOM | `nix-store --query --requisites /run/current-system` |
| Generation history | `nixos-rebuild list-generations` |
| Store integrity | `nix-store --verify --check-contents` |

## QSA/Assessor Differentiators

When presenting to compliance assessors, emphasize:
1. Immutable infrastructure — stronger than traditional FIM
2. Declarative-only config — no undocumented manual changes
3. Atomic rollback — instant recovery to known-good state
4. Complete BOM — cryptographically verifiable at any time
5. Reproducible builds — assessor can verify by rebuilding

## Key Takeaways

- Several traditionally difficult controls (CM-2, CM-6, CM-7, CM-11, SI-3, SI-7) are **structurally enforced** by NixOS rather than add-on tooling
- This is the strongest argument for NixOS as a compliance platform
- But watch the [[nixos-gotchas]] — Nix store readability, path differences, and nftables defaults can trip you up
