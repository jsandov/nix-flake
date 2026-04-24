# PCI DSS v4.0 Highlights

Key findings from the PCI DSS module — best overall quality in the PRD suite.

## Scoping Decision

Server enters PCI scope if it processes/stores/transmits CHD/SAD, provides security services to CDE, shares network segment, or agents access payment APIs. Recommended: maintain as out-of-scope via network segmentation.

## GPU VRAM as CHD Residue

When running LLM inference with CHD in prompts:
- VRAM retains CHD fragments until overwritten
- KV cache holds CHD tokens until session ends
- System RAM may contain spilled context
- Unencrypted swap could persist CHD to disk

**Mitigations:** Encrypted swap, clear model context between CHD sessions (`keep_alive: 0` API call), document in targeted risk analysis.

## v4.0 New Requirements (Effective March 2025)

| Req | What's New |
|---|---|
| 5.2.3.1 | Risk analysis for systems without traditional AV — NixOS immutability argument |
| 8.4.3 | MFA for ALL non-console admin access |
| 10.4.1.1 | Automated audit log reviews |
| 10.6.1-3 | Explicit NTP synchronization |
| 11.3.1.3 | Authenticated internal vulnerability scanning |
| 12.10.7 | Detect unexpected PAN storage |

## Anti-Malware + NixOS (Req 5)

`nix store verify --all` is **strictly stronger** than signature-based AV — detects ANY modification via cryptographic content hashing.

**Strategy:**
- ClamAV with `OnAccessIncludePath` for writable paths (`/var/lib`, `/tmp`, `/home`)
- Exclude `/nix/store` from ClamAV (justified by content-addressed hashing)
- Daily `nix store verify --all` with alerting on corruption
- Weekly full ClamAV scan of writable paths
- Document in targeted risk analysis per 5.2.3.1

## Vulnerability Scanning (Req 11) — Three Layers

1. **vulnix** — package CVE audit (not a network scanner)
2. **Lynis** — host security hardening assessment (CIS benchmarks)
3. **OpenVAS/Nessus/Qualys** — **required** network vulnerability scanner

vulnix + Lynis alone do NOT satisfy 11.3.1. A dedicated network scanner is mandatory.

## CVSS Remediation Timelines

Critical: 30d, High: 90d, Medium: 180d, Low: next update

## AIDE Paths (NixOS-Specific)

Monitor: `/etc`, `/boot`, `/run/current-system`, `/etc/static`, `/etc/shadow`, `/etc/ssh`, `/var/log/audit`, `/etc/pam.d`, `/etc/nftables.conf`

**Do NOT monitor** `/usr/bin`, `/usr/sbin` — empty on NixOS. See [[../nixos-platform/nixos-gotchas]].

## Centralized Log Forwarding (Req 10.3.3)

rsyslog with RELP/TLS to SIEM. Local-only logs fail 10.3.3. Without a functioning SIEM receiver, this is a gap.

## TLS Certificate Inventory (Req 4.2.1.2)

Must track: Nginx TLS cert/key, SSH host key, syslog CA cert, sops-nix age key. Reviewed annually.

## Key Takeaways

- PCI DSS v4.0 has significant new requirements effective March 2025 — most are already covered
- The NixOS immutability argument for anti-malware is strong but needs formal risk analysis documentation
- Network vulnerability scanning is a gap — vulnix/Lynis are not sufficient alone
- [[../compliance-frameworks/canonical-config-values]] resolves all PCI vs other framework conflicts
