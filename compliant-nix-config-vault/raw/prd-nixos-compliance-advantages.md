# NixOS as a Compliance Platform — Unique Advantages

Source: prd-nist-800-53.md Appendix B, prd-pci-dss.md Assessor Guidance, MASTER-REVIEW.md

## Structural Compliance Properties

NixOS provides properties that make several traditionally difficult controls **structurally enforced by the OS design** rather than by add-on tooling:

### 1. Declarative State (CM-2, CM-6)
- Entire system configuration is defined in code
- No configuration drift from imperative changes
- System state is derived from the flake on each rebuild
- Every enabled service, open port, user account, firewall rule is visible in code

### 2. Immutable Store (SI-3, SI-7, SR-9, SR-11)
- `/nix/store` is read-only and content-addressed
- Every path is derived from cryptographic hash of all inputs
- Built-in tamper detection — ANY modification changes the hash
- `nix store verify --all` is **strictly stronger** than signature-based AV
- Traditional Linux requires additional tooling (AIDE, Tripwire) to achieve this

### 3. Atomic Upgrades and Rollback (CP-10, SI-2, CM-3)
- Updates are atomic — no partial-update state
- Previous generations retained and selectable at boot
- `nixos-rebuild switch --rollback` for instant recovery
- Supports incident response and change management

### 4. Reproducible Builds (CM-2, SA-10)
- Same flake inputs → identical system on different hardware
- `flake.lock` provides cryptographic record of all dependency versions
- Supports disaster recovery and evidence consistency

### 5. No User-Installed Software (CM-11, CM-7)
- `users.mutableUsers = false` means only declared accounts exist
- `nix.settings.allowed-users` restricts who can use Nix CLI
- No `apt install` equivalent for non-admin users
- Package management restricted to authorized users via config changes

### 6. Garbage Collection (MP-6, SR-12)
- `nix-collect-garbage -d` deterministically removes all unreferenced store paths
- Supports secure decommissioning of old software versions

## Evidence Generation Capabilities

| Evidence Type | Method | Use |
|---|---|---|
| System config snapshot | `nixos-rebuild dry-build` + Git hash | Exact config at any point in time |
| User account inventory | `nix eval .#nixosConfigurations.server.config.users.users --json` | Unique user identification |
| Open port inventory | `nix eval .#config.networking.firewall --json` | Network access controls |
| Package closure | `nix-store --query --requisites /run/current-system` | Complete bill of materials |
| Generation history | `nixos-rebuild list-generations` | Change management timeline |
| Flake metadata | `nix flake metadata` | Input provenance |
| Store integrity | `nix-store --verify --check-contents` | Tamper detection |

## QSA/Assessor Differentiators

When presenting to PCI QSA or compliance assessors:

1. **Immutable infrastructure** — Nix store is read-only, content-addressed. Stronger than traditional FIM.
2. **Declarative-only configuration** — `users.mutableUsers = false` + flake means no undocumented manual changes.
3. **Atomic rollback** — returns entire system to previous known-good state in seconds.
4. **Complete BOM** — `nix-store --query --requisites` provides cryptographically verifiable software inventory at any time.
5. **Reproducible builds** — assessor can verify declared config produces expected system by rebuilding.

## NixOS-Specific Gotchas for Compliance

1. **Nix store is world-readable** — secrets must NEVER end up in store paths. Use sops-nix/agenix.
2. **NixOS paths are different** — `/usr/bin`, `/usr/sbin` don't exist. Binaries are in `/nix/store` exposed via `/run/current-system/sw/bin/`
3. **AIDE must monitor NixOS-correct paths** — `/run/current-system/sw/bin`, `/etc`, `/boot`, NOT `/usr/bin`
4. **nftables is the default** in NixOS 24.11+ — iptables extraCommands may silently fail
5. **Flake lock staleness** — locked flake pins all packages. Must update regularly to avoid unpatched CVEs. But updates may introduce regressions.
