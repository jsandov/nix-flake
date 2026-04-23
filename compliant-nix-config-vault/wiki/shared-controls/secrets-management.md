# Secrets Management

sops-nix (or agenix) for the complete secrets lifecycle.

## Why This is Non-Negotiable

The Nix store is **world-readable** (0444/0555). Any secret that ends up in a store path is accessible to every user and process. See [[nixos-platform/nixos-gotchas]] for common leakage vectors.

## How sops-nix Works

1. Secrets encrypted at rest in Git repository using age keys
2. Decrypted at activation time to `/run/secrets/` (tmpfs — not persisted to disk)
3. Never present in the Nix store or in plaintext in any committed file
4. Each secret has defined owner, group, and permissions

## Secret Types and Rotation

| Secret Type | Rotation Schedule |
|---|---|
| TLS certificates | Annual (or 90-day for PCI) |
| SSH host keys | On compromise |
| API tokens | Quarterly |
| LUKS passphrases | On compromise |
| TOTP seeds | On compromise |
| Backup encryption keys | On compromise |

## Rules

- **Never** embed secrets in Nix expressions
- **Never** use `pkgs.writeText` with secret content
- **Never** interpolate secrets in environment variables visible to AI services
- **Always** reference runtime secret paths (e.g., `/run/secrets/tls-key`)
- **Always** audit the Nix store periodically for accidentally committed secrets

## Key Takeaways

- Secrets management is the #1 operational risk on NixOS — store readability makes it critical
- sops-nix and agenix are functionally equivalent — pick one and use it consistently
- Rotation schedules align with [[compliance-frameworks/canonical-config-values]]
- For HIPAA: terminated user's age key must be removed from recipients + all secrets re-encrypted
