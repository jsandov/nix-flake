# PCI DSS v4.0 Highlights — Key Findings

Source: prd-pci-dss.md (scored 7.1/10, best module quality)

## Scoping Decision

Server enters PCI scope if it processes/stores/transmits CHD/SAD, provides security services to CDE, shares network segment with CDE, or agents have access to payment APIs/databases.

**Recommended posture:** Maintain as "connected-to" or "out-of-scope" via network segmentation. Even out of scope, implementing controls provides defense-in-depth.

## GPU VRAM as Potential CHD Residue

When running LLM inference, CHD in prompts may persist in:
- GPU VRAM (until overwritten by next inference)
- KV cache (until session ends/context evicted)
- System RAM (model offloading)
- Swap (if unencrypted)

Recommendations: encrypted swap, clear model context between CHD sessions, treat VRAM as volatile CHD storage, document in targeted risk analysis.

## v4.0 New Requirements (Effective March 2025)

Key newly mandatory requirements:
- **5.2.3.1:** Risk analysis for systems not using traditional AV (NixOS immutability argument)
- **8.4.3:** MFA for ALL non-console admin access (not just CDE)
- **10.4.1.1:** Automated audit log reviews (multi-rule anomaly detection)
- **10.6.1-3:** Explicit NTP synchronization requirements
- **11.3.1.3:** Authenticated internal vulnerability scanning
- **12.10.7:** Detect unexpected PAN storage (PAN scanning automation)

## Anti-Malware and NixOS Immutability (Req 5)

NixOS Nix store is read-only, content-addressed. `nix store verify --all` is **strictly stronger** than signature-based AV for detecting tampering.

Approach: Deploy ClamAV with on-access scanning for writable paths + periodic full scans. Exclude `/nix/store` from ClamAV (justified by content-addressed hashing). Daily `nix store verify --all` with alerting.

**QSAs may still require AV** — document NixOS immutability in targeted risk analysis.

## Vulnerability Scanning (Req 11)

Three layers needed:
1. **vulnix** — package CVE audit against NVD (not a network scanner)
2. **Lynis** — host security hardening assessment (CIS benchmarks)
3. **Network vulnerability scanner** (OpenVAS/Nessus/Qualys) — **required for 11.3.1 compliance**

vulnix and Lynis alone do NOT satisfy PCI DSS 11.3.1.

## CVSS-Based Remediation Timelines

| CVSS | Severity | Timeline |
|---|---|---|
| 9.0-10.0 | Critical | 30 calendar days |
| 7.0-8.9 | High | 90 calendar days |
| 4.0-6.9 | Medium | 180 calendar days |
| 0.1-3.9 | Low | Next scheduled update |

## File Integrity Monitoring (Req 11.5.2)

NixOS-specific AIDE paths:
- `/etc`, `/boot` — standard
- `/run/current-system` — NixOS system closure symlink
- `/etc/static` — NixOS-generated config
- `/etc/shadow`, `/etc/passwd`, `/etc/ssh` — credentials
- `/var/log/audit`, `/etc/audit` — audit config
- `/etc/pam.d`, `/etc/nftables.conf` — security controls

**Do NOT monitor** `/usr/bin`, `/usr/sbin` — they're empty on NixOS.

## Centralized Log Forwarding (Req 10.3.3)

rsyslog with RELP/TLS for guaranteed delivery. Local-only logs fail 10.3.3. Needs functioning SIEM receiver.

## TLS Certificate Inventory (Req 4.2.1.2, effective March 2025)

Must track: Nginx TLS cert, Nginx TLS key, SSH host key, syslog CA cert, sops-nix age key. Reviewed annually, updated on any cert change.

## Automated Log Review (Req 10.4.1.1)

Multi-rule anomaly detection covering:
1. Auth failures exceeding 3x baseline
2. Privilege escalation attempts
3. After-hours admin access
4. New account creation
5. Audit subsystem modification
6. Credential file changes

Production CDE should supplement with SIEM-based correlation.
