# Canonical Configuration Values — Resolved Cross-Framework Conflicts

Source: prd.md Appendix A

These values are the **single source of truth** for the implementation flake. When any module PRD's snippet differs from these, the Appendix A values win.

## Service Binding

| Setting | Value | Rationale |
|---|---|---|
| Ollama listen | `127.0.0.1:11434` | Ollama has no auth; LAN via Nginx TLS proxy |
| Ollama ORIGINS | `http://127.0.0.1:*` | Prevents cross-origin bypass |
| SSH listen | LAN interface only (e.g., `192.168.1.50`) | Not `0.0.0.0` |
| App API (8000) | `127.0.0.1:8000` via Nginx TLS proxy | Same pattern as Ollama |

## Firewall

- **Backend:** nftables exclusively (NixOS 24.11 default)
- **Default policy:** deny inbound, explicit allowlist per interface
- **Egress:** per-UID output filtering via nftables `meta skuid`
- **Do NOT use** `networking.firewall.extraCommands` with iptables syntax

## systemd Hardening

| Setting | Value | Applies To |
|---|---|---|
| MemoryDenyWriteExecute | **true** | All non-GPU services |
| MemoryDenyWriteExecute | **omit** | Ollama, any CUDA service (CUDA needs W+X for JIT) |
| ProtectSystem | **"strict"** | All services including Ollama |
| NoNewPrivileges | true | All services |
| PrivateTmp | true | All services |
| ProtectHome | true | All services |

## SSH Configuration

| Setting | Value | Reason |
|---|---|---|
| PasswordAuthentication | false | Key-only |
| KbdInteractiveAuthentication | **true** | Required for TOTP MFA |
| AuthenticationMethods | `"publickey,keyboard-interactive"` | MFA: key + TOTP |
| PermitRootLogin | "no" | Consensus |
| Ciphers | AES-GCM + AES-CTR (no ChaCha20 for FIPS) | STIG FIPS |
| Macs | ETM variants only | Stronger than non-ETM |
| ClientAliveInterval | 600 | STIG resolved |
| ClientAliveCountMax | 0 | Disconnect immediately |
| **DO NOT USE** Protocol 2 | Removed from OpenSSH 7.6+ | Breaks sshd |
| **DO NOT USE** ChallengeResponseAuthentication | Deprecated alias | Conflicts |

## Log Retention

| Log Type | Retention | Framework |
|---|---|---|
| Systemd journal | 365 days | PCI DSS 10.5.1 |
| Journal disk | 10G | Operational |
| AI decision logs | 18 months | EU AI Act Art. 12 |
| Policy docs | 6 years | HIPAA §164.316(b) |

## Authentication & Accounts

| Setting | Value | Driver |
|---|---|---|
| Password min length | 15 chars | STIG/HITRUST |
| Password history | 24 | HITRUST Level 2 |
| Password max age | 60 days | STIG |
| Lockout threshold | 5 attempts | STIG/HITRUST |
| Lockout duration | 1800s (30 min) | HITRUST/PCI |
| Shell TMOUT | 600s | STIG |
| sudo timestamp | 5 minutes | NIST IA-11 |

## Patching

| Severity | Timeline |
|---|---|
| Critical | 30 days |
| High | 90 days |
| Medium | 180 days |
| Zero-day (exploited) | 72 hours (best effort) |

## Scanning Schedule

| Scan | Frequency |
|---|---|
| AIDE integrity | Hourly |
| vulnix CVE | Weekly |
| nix-store --verify | Daily |
| ClamAV | Weekly |
| Lynis | Monthly |
| OpenVAS/Nessus | Quarterly |
| PCI segmentation | Every 6 months |
| Compliance evidence | Weekly + on every rebuild |

## Encryption

- TLS min: 1.2
- TLS ciphers: AEAD-only (no CBC), explicit list not `HIGH:!aNULL:!MD5:!RC4`
- Disk: LUKS2 with AES-256-XTS
- Swap: LUKS-based (not deprecated `swapDevices.*.encrypted`)

## FIPS Mode

- **Algorithm-compatible, not FIPS-validated** — NixOS has no FIPS-validated OpenSSL
- **Do NOT** set `fips=yes` in openssl.cnf without FIPS provider loaded
- Ed25519 SSH keys allowed with documented exception

## Kernel Module Blacklist (stig-baseline owns this)

cramfs, freevxfs, jffs2, hfs, hfsplus, squashfs, udf, dccp, sctp, rds, tipc, bluetooth, btusb, cfg80211, mac80211, firewire-core/ohci/sbp2/net + legacy, thunderbolt, usb-storage, uas, pcspkr, snd_pcsp, floppy

## NixOS-Specific Options (set exactly once)

| Option | Value | Owner |
|---|---|---|
| users.mutableUsers | false | stig-baseline |
| nix.settings.allowed-users | `[ "admin" ]` | stig-baseline |
| boot.loader.systemd-boot.editor | false | stig-baseline |
| systemd.ctrlAltDelUnit | "" | stig-baseline |
| systemd.coredump.extraConfig | "Storage=none" | stig-baseline |
| kernel.core_pattern | `"|/bin/false"` | stig-baseline |
| networking.wireless.enable | false | lan-only-network |
| services.xserver.enable | false | stig-baseline |
