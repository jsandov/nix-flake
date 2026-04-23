# Shared Requirements — Controls Demanded by Multiple Frameworks

Source: prd.md Section 7

These are implemented once in the appropriate flake module and satisfy requirements across all 10 frameworks.

## 7.1 Full-Disk Encryption (LUKS)
- LUKS2 with AES-256-XTS
- Covers: model artifacts, prompts, logs, config, outputs
- Keys managed outside Nix store
- Satisfies: NIST SC-28, HIPAA encryption, PCI DSS Req 3, HITRUST, STIG

## 7.2 SSH Hardening
- Key-based only, no password/keyboard-interactive for passwords
- No root login, restricted AllowUsers
- MFA: TOTP via google-authenticator PAM
- Idle session termination, X11 forwarding disabled

## 7.3 Audit Logging
- auditd for kernel events, journald for service logs
- Persistent storage, min 1 year retention (PCI DSS)
- No secrets/credentials/unmasked sensitive data in logs
- Log integrity protected against tampering

## 7.4 NTP Synchronization
- Chrony to authoritative sources
- Required for log correlation and certificate validation

## 7.5 File Integrity Monitoring (AIDE)
- Hourly scheduled checks against known-good baseline
- Alerts on unauthorized changes
- Baseline regenerated after authorized changes
- NixOS-correct paths: `/run/current-system/sw/bin`, `/etc`, `/boot`, `/var/lib/ollama/models`

## 7.6 Egress Filtering
- Outbound restricted to approved destinations
- Unauthorized egress blocked and logged
- Prevents data exfiltration, unauthorized model downloads, agent external connections

## 7.7 Agent Sandboxing
- systemd isolation: NoNewPrivileges, PrivateTmp, ProtectSystem=strict
- Restricted address families, resource quotas
- Explicit ReadWritePaths only
- Primary mitigation for OWASP Agentic AI threats

## 7.8 Model Provenance Verification
- Checksums/signatures verified before deployment
- Model registry tracks: source, version, hash, deployment history
- AIDE detects unauthorized substitution
- **Limitation:** trust-on-first-download (Ollama has no cryptographic attestation)

## 7.9 Evidence Generation Automation
- Scripts produce: config snapshots, audit log extracts, AIDE reports, firewall dumps, user listings, service inventories, encryption status
- Timestamped, stored for audit retrieval
- Runs weekly + on every `nixos-rebuild switch`

## 7.10 Incident Response Hooks
- Triggers: AIDE drift, failed auth spikes, unauthorized egress, sandbox violations, service anomalies
- Notify designated personnel
- Can trigger automated containment (service restart, network isolation)

## 7.11 Backup and Recovery
- System config recoverable from Git-managed flake
- Data backups: model artifacts, logs, app state (encrypted)
- Fresh NixOS deployment rebuildable from flake without manual steps
- Generation rollback for immediate recovery

## 7.12 Vulnerability Management
- Track NixOS security advisories and upstream CVEs
- vulnix scans closure for known CVEs
- NVIDIA driver updates tested against hardened baseline
- Patch timelines: Critical 30d, High 90d, Medium 180d, Zero-day 72h

## 7.13 Secrets Management
- sops-nix with age encryption (or agenix)
- Encrypted at rest in Git, decrypted at activation to `/run/secrets/` (tmpfs)
- Not in Nix store, not in plaintext in any committed file
- Rotation: TLS annual, SSH host keys on compromise, API tokens quarterly

## 7.14 Boot Integrity
- UEFI Secure Boot enabled
- Verified via `mokutil --sb-state`
- LUKS depends on boot integrity

## 7.15 Account Lifecycle Management
- Declarative via `users.users` — remove user from config + rebuild
- Quarterly access reviews
- Credential rotation: SSH keys annually, TOTP on compromise, service tokens quarterly
- Full audit trail via Git history + auditd

## 7.16 Data Classification

| Level | Label | Examples | Handling |
|---|---|---|---|
| 1 | Public | Published model metadata | Integrity only |
| 2 | Internal | Inference logs, system config | Encrypted at rest, restricted access |
| 3 | Sensitive | ePHI, CHD, PII | Encrypted everywhere, audit-logged, masked in logs |
| 4 | Restricted | LUKS passphrases, age keys, TLS keys | sops-nix only, never plaintext |
