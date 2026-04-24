# Canonical Configuration Values

The **single source of truth** for the implementation flake. When any module PRD's inline snippet differs, these values win.

## Service Binding

| Setting | Value | Rationale |
|---|---|---|
| Ollama listen | `127.0.0.1:11434` | No auth in Ollama; LAN via Nginx TLS proxy |
| Ollama ORIGINS | `http://127.0.0.1:*` | Prevent cross-origin bypass |
| SSH listen | LAN interface only | Not `0.0.0.0` |
| App API (8000) | `127.0.0.1:8000` via Nginx | Same localhost pattern |

## Firewall

- **Backend:** nftables exclusively (NixOS 24.11 default)
- **Do NOT use** `networking.firewall.extraCommands` with iptables syntax
- Default deny inbound, explicit allowlist per interface
- Egress: per-UID filtering via nftables `meta skuid`

## systemd Hardening

| Directive | Non-GPU Services | CUDA/GPU Services |
|---|---|---|
| MemoryDenyWriteExecute | **true** | **omit** (CUDA needs W+X) |
| ProtectSystem | "strict" | "strict" |
| NoNewPrivileges | true | true |
| PrivateTmp | true | true |

See [[../ai-security/ai-security-residual-risks]] for CUDA incompatibility details.

## SSH (Appendix A.4)

| Setting | Value |
|---|---|
| PasswordAuthentication | false |
| KbdInteractiveAuthentication | **true** (for TOTP MFA) |
| AuthenticationMethods | `"publickey,keyboard-interactive"` |
| Ciphers | AES-GCM + AES-CTR (no ChaCha20 for FIPS) |
| Macs | ETM variants only |
| ClientAliveInterval | 600 |
| ClientAliveCountMax | 0 |

**Do NOT use:** `Protocol 2` (removed OpenSSH 7.6), `ChallengeResponseAuthentication` (deprecated alias)

## Authentication & Accounts (A.6)

| Setting | Value | Driver |
|---|---|---|
| Password min length | 15 chars | STIG/HITRUST |
| Password history | 24 | HITRUST L2 |
| Password max age | 60 days | STIG (NIST 800-63B tension — see `docs/resolved-settings.yaml`) |
| Lockout threshold | 5 attempts | STIG/HITRUST |
| Lockout duration | 1800s (30 min) | HITRUST/PCI |
| Lockout find interval | 900s (15 min) | STIG/HITRUST |
| Shell TMOUT | 600s | STIG |
| SSH idle timeout | 600s | STIG |
| MFA scope | all-remote-admin | STIG/HITRUST/PCI |
| MFA mechanism | TOTP (Google Authenticator PAM) + FIDO2 ed25519-sk | HIPAA/HITRUST |

## Log Retention (A.5)

| Type | Retention |
|---|---|
| Systemd journal | 365 days |
| AI decision logs | 18 months (EU AI Act) |
| Policy docs | 6 years (HIPAA) |

## Scanning Schedule (A.8)

| Scan | Frequency |
|---|---|
| AIDE integrity | Hourly |
| vulnix CVE | Weekly |
| nix-store --verify | Daily |
| ClamAV | Weekly |
| Lynis | Monthly |
| Network vuln scan | Quarterly |
| Compliance evidence | Weekly + on rebuild |

## Patching (A.7)

| Severity | Timeline |
|---|---|
| Critical | 30 days |
| High | 90 days |
| Medium | 180 days |
| Zero-day | 72 hours |

## Key Takeaways

- All inline Nix snippets in framework PRDs are **illustrative only** — this appendix is canonical
- FIPS mode is algorithm-compatible, not FIPS-validated (NixOS has no validated OpenSSL)
- The `stig-baseline` module owns all NixOS options that must be set exactly once
- Kernel module blacklist is the STIG superset — owned by `stig-baseline` only
