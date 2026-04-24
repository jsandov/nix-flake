# Secrets Management

**sops-nix** — committed. See `modules/secrets/default.nix` for the authoritative per-secret declaration list and [[canonical-config]] for how this fits into the declare-once-consume-everywhere pattern.

## Why This is Non-Negotiable

The Nix store is **world-readable** (0444/0555). Any secret that ends up in a store path is accessible to every user and process. See [[../nixos-platform/nixos-gotchas]] for common leakage vectors.

## Project Decision — sops-nix, Not agenix

Both tools decrypt into `/run/secrets/` at activation time and are functionally equivalent for the threat model. The project commits to sops-nix to prevent the divergence that an open "either/or" invited across seven PRDs. Agenix is not supported; hosts that ship an agenix-style secret declaration will fail PR review.

## How sops-nix Works

1. Secrets encrypted at rest in the Git repository using age public keys.
2. Decrypted at activation time to `/run/secrets/` — a tmpfs, not persisted to disk.
3. Never present in the Nix store or in plaintext in any committed file.
4. Each secret has a declared owner, group, and mode (see `modules/secrets/default.nix`).

## Age Key Provisioning

Operator procedure, deliberately outside Nix so the private key never lives in the repo or store:

1. **On a trusted workstation**: `age-keygen -o ~/.config/sops/age/keys.txt`.
2. **Publish the public key** (`age1...`) into `.sops.yaml` recipient list so sops can encrypt for it.
3. **On the server**: `/var/lib/sops-nix/key.txt` must contain the private age key. Provisioned via physical console or a one-shot SSH session during initial bring-up.
4. **Rotation**: on compromise of any recipient, remove that public key from `.sops.yaml`, re-encrypt all secrets (`sops updatekeys secrets/secrets.enc.yaml`), and commit the re-encrypted file.

## Secret Catalogue (from `modules/secrets/default.nix`)

| Name | Owner | Mode | Path | Purpose |
|---|---|---|---|---|
| `tls/ai-server.crt` | nginx:nginx | 0440 | `/run/secrets/tls/ai-server.crt` | Nginx reverse proxy TLS cert |
| `tls/ai-server.key` | nginx:nginx | 0400 | `/run/secrets/tls/ai-server.key` | Nginx reverse proxy TLS key |
| `tls/syslog-ca.pem` | syslog:syslog | 0440 | `/run/secrets/tls/syslog-ca.pem` | Remote syslog RELP TLS CA |
| `ssh/host-ed25519-key` | root:root | 0400 | `/etc/ssh/ssh_host_ed25519_key` | sshd host key (fixed path) |
| `luks/passphrase-backup` | root:root | 0400 | `/run/secrets/luks/passphrase-backup` | Offline recovery; not used at runtime |
| `api/ollama-control-token` | ollama:ollama | 0400 | `/run/secrets/api/ollama-control-token` | Internal Ollama API auth |
| `api/ai-services-signing-key` | ai-services:ai-services | 0400 | `/run/secrets/api/ai-services-signing-key` | Response signing |
| `totp/admin-google-authenticator` | admin:admin | 0400 | `/home/admin/.google_authenticator` | PAM TOTP seed (fixed path) |
| `backup/encryption-key` | root:root | 0400 | `/run/secrets/backup/encryption-key` | Independent of LUKS |
| `syslog/relp-psk` | syslog:syslog | 0400 | `/run/secrets/syslog/relp-psk` | PSK fallback when mTLS unavailable |

## Rotation Schedule

Declared in `config.secrets.rotationDays` (in `modules/secrets/default.nix`); consumed by evidence generation (ARCH-10).

| Category | Cadence | Driving framework |
|---|---|---|
| TLS certificates | 90 days | PCI DSS 4.2.1 |
| SSH host keys | On compromise | All |
| LUKS passphrases | On compromise | HIPAA §164.312(a)(2)(iv) |
| API tokens | 90 days | NIST IA-5, PCI 8.6.3 |
| TOTP seeds | On compromise | Operational |
| Backup encryption keys | On compromise | HIPAA §164.308(a)(7) |
| Syslog RELP secrets | 90 days | HIPAA §164.312(e) |

## Rules

- **Never** embed secrets in Nix expressions.
- **Never** use `pkgs.writeText` / `builtins.toFile` with secret content.
- **Never** interpolate secrets into environment variables on AI services.
- **Always** reference runtime paths via `config.sops.secrets.<name>.path`.
- **Always** audit the Nix store periodically (ARCH-07 lint) for accidentally committed secrets.

## Evaluator vs Deployment

The skeleton ships `secrets/secrets.enc.yaml` as a plain-text placeholder so `nix flake check` and `nix eval` can resolve the path. `sops.validateSopsFiles = false` suppresses format validation at eval time. The first real deployment must:

1. Encrypt `secrets/secrets.enc.yaml` with sops (replacing the placeholder body).
2. Set `sops.validateSopsFiles = true` in the host config to re-enable format checks.

See [[nixos-gotchas#12-handcrafting-flakelock-without-a-nix-cli|the flake.lock bootstrap gotcha]] for the parallel pattern.

## Key Takeaways

- sops-nix is committed. Agenix is rejected, not deferred.
- Age private key never enters the repository or the Nix store — operator procedure only.
- Every secret is declared in `modules/secrets/default.nix` with owner, mode, and path.
- Rotation cadence surfaces to evidence generation via `config.secrets.rotationDays`.
- `validateSopsFiles = false` is a skeleton-only setting; real deployments re-enable it.
