# NixOS Platform

Why NixOS is uniquely suited as a compliance platform, and the gotchas to watch for.

## Articles

- [[compliance-advantages]] — Six structural properties that make compliance easier
- [[nixos-gotchas]] — NixOS-specific pitfalls for compliance implementations
- [[github-actions-nix-stack]] — Installer, cache, and lint action choices for CI (2026)
- [[skeleton-secrets-pattern]] — How to declare sops-nix secrets so `nix flake check` succeeds without real encryption
- [[nixos-audit-rule-paths]] — Path mapping for auditd, AIDE, and sudo `secure_path` on NixOS
- [[nftables-translation-reference]] — iptables → nftables translation, hook/priority cheat-sheet, structured-table pattern
- [[auditd-module-pattern]] — `security.auditd` + `security.audit` setup, failureMode trade-off, `-e 2` lock, auid filters
