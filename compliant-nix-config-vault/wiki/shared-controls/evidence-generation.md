# Evidence Generation

Automated compliance evidence collection — reduces manual audit burden across all frameworks.

## What Gets Collected

| Evidence | Method | Use |
|---|---|---|
| Account inventory | `getent passwd` + `getent group` | AC-2, unique user ID proof |
| Firewall rules | `nft list ruleset` | SC-7, network boundary proof |
| Audit rules | `auditctl -l` | AU-2, audit config proof |
| Package inventory | `nix-store --query --requisites /run/current-system` | CM-8, complete BOM |
| Generation list | `nixos-rebuild list-generations` | CM-2, change history |
| SSH config | `sshd -T` | IA-2, authentication proof |
| LUKS status | `cryptsetup status` | SC-28, encryption proof |
| Store verification | `nix-store --verify` | SI-7, integrity proof |
| Flake metadata | `nix flake metadata --json` | SR-4, provenance proof |
| NixOS version | `nixos-version` | CM-8, system identity |

## Collection Schedule

- **Weekly** via systemd timer
- **On every `nixos-rebuild switch`** via system activation script
- Evidence timestamped and stored in `/var/lib/compliance-evidence/YYYYMMDD/`
- SHA256 manifest generated for each snapshot

## Key Takeaways

- Evidence generation is fully automated — no manual collection needed
- Covers requirements across NIST, HIPAA, PCI DSS, HITRUST, and STIG simultaneously
- The `system.activationScripts.compliance-evidence` trigger ensures evidence is captured on every config change
- Evidence directory should be included in backup schedule
