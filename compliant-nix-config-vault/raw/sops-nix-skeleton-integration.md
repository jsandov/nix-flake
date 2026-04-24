# sops-nix skeleton integration — decisions and placeholder pattern

Session notes from implementing ARCH-05 (add sops-nix as a flake input, create `modules/secrets/default.nix`, commit the project to sops-nix over agenix). Captures the non-obvious choices for the next compile pass.

## Why sops-nix, not agenix

MASTER-REVIEW action plan item #5 demanded a committed choice. The PRD prose said "sops-nix OR agenix" in seven places across four PRDs — classic divergence bait. Picking sops-nix forecloses that divergence. The tools are functionally equivalent for the threat model (both decrypt to `/run/secrets/` at activation, both keep private keys outside the store). The decision is about project discipline, not technical merit.

Deleted / normalised occurrences:

- `docs/prd/prd.md` §7.13 — removed "Alternative: agenix may be used...".
- `docs/prd/prd-nist-800-53.md` IA-5, SC-12, TLS lifecycle — normalised to sops-nix.
- `docs/prd/prd-hipaa.md` §3.3 termination, §5.4 RELP, §5.5.2 key mgmt, §8 rules, §12 matrix — normalised.
- `docs/prd/prd-pci-dss.md` 3.6.1 table — normalised.
- `docs/prd/prd-hitrust.md` line 1189 TLS comment — normalised.
- `docs/prd/prd-owasp.md` code snippet comment — normalised.
- Wiki articles updated: `secrets-management.md` (rewritten around the committed choice), `nixos-gotchas.md` (entries 1 + key takeaway), `shared-controls-overview.md` (table cell), `shared-controls/_index.md`, `review-findings/lessons-learned.md`.

Left intentionally: `MASTER-REVIEW.md` action-plan items #3 and #5 — historical record of what the plan *said*, not current project truth.

## Placeholder encrypted file — why CI can eval without real secrets

The skeleton ships `secrets/secrets.enc.yaml` as a plain-text placeholder. Three things combine to let eval succeed without real encryption:

1. `sops.defaultSopsFile = ../../secrets/secrets.enc.yaml` — a Nix path literal. Nix copies this file into the store at eval so the path resolves. The file must exist in the repo; its *contents* do not have to be real sops output.
2. `sops.validateSopsFiles = false` — disables the eval-time format check that would otherwise reject a non-sops file. sops-nix exposes this knob specifically for test and skeleton scenarios.
3. No decryption ever happens at eval. Secret decryption is a systemd activation step, which CI's `nix eval` never reaches.

Real deployments must:
- Encrypt the file body with `sops secrets/secrets.enc.yaml` (keeping the same path).
- Flip `validateSopsFiles` back to `true` in the host config.
- Provision `/var/lib/sops-nix/key.txt` with the age private key.

## Age key — out-of-band by design

`sops.age.generateKey = false` is deliberate. Auto-generation would write a key under the Nix store, defeating the entire threat model — the Nix store is world-readable. The operator procedure lives in the wiki (`wiki/shared-controls/secrets-management.md`), not in Nix. The three steps:

1. `age-keygen -o ~/.config/sops/age/keys.txt` on a trusted workstation.
2. Publish the public key into `.sops.yaml` recipient list.
3. Copy the private key to `/var/lib/sops-nix/key.txt` on the server via physical console or one-shot SSH.

This is one of the rare cases where *not* automating is the correct security choice.

## Secret namespace scheme

Secrets use `<category>/<id>` names. Categories match the rotation-schedule buckets:

- `tls/*` — certificates and keys for Nginx and syslog RELP
- `ssh/*` — SSH host keys (path overridden to `/etc/ssh/ssh_host_*_key` so sshd reads them directly)
- `luks/*` — LUKS passphrase backup for disaster recovery
- `api/*` — internal API tokens (Ollama control, ai-services signing)
- `totp/*` — TOTP seed files (path overridden to `/home/<user>/.google_authenticator`)
- `backup/*` — backup encryption (independent of LUKS)
- `syslog/*` — RELP PSK fallback

The "fixed path" overrides matter: `path = "/etc/ssh/ssh_host_ed25519_key"` and `path = "/home/admin/.google_authenticator"` place the decrypted file where the consuming service expects it, rather than forcing a symlink or wrapper.

## `config.secrets.rotationDays` — a local convention, not sops-nix

Added `options.secrets.rotationDays` with `types.attrsOf types.ints.positive`, keyed by category. Default values match the rotation schedule documented in the wiki. ARCH-10 (evidence generation) will consume this option to emit a rotation-status report without sops-nix needing to know anything about rotation cadence.

The choice to expose this as `options.secrets.*` rather than `options.canonical.*` is deliberate: canonical holds Appendix A values that are truly cross-framework resolved; rotation cadence is operational metadata specific to the secrets module.

## Gotchas encountered

- **Nix path literals must exist at eval.** `defaultSopsFile = ../../secrets/secrets.enc.yaml` fails if the file is missing — even when `validateSopsFiles = false`. Path resolution happens before the sops module runs. Placeholder file is mandatory.
- **`age.keyFile` is a string path**, not a Nix path literal. It doesn't need to exist at eval; sops reads it at activation. That difference matters — if it were a Nix path, we'd need a placeholder for it too.
- **Secret `path` overrides** are strings, not Nix paths. Same reasoning: sops-nix materialises them at activation, not at eval.
- **`inputs.nixpkgs.follows = "nixpkgs"` on sops-nix** keeps the dependency graph clean — otherwise sops-nix pulls its own nixpkgs and `flake.lock` gets two versions. Always use `follows`.
- **Mixing top-level `sops = { ... }` with `options.secrets.* = ...`** fails with "has an unsupported attribute `sops`. This is caused by introducing a top-level `config' or `options' attribute." Once a module uses `options.*` explicitly, every config assignment must live under `config = { ... };`. Caught on first CI run; fixed by wrapping sops settings in `config.sops = { ... }`. The module-system rule is: top-level attrs are implicit config *only if you never use explicit `options`*; the moment you do, everything has to be under one or the other.

## Suggested wiki compile targets

- `wiki/shared-controls/secrets-management.md` — already rewritten in this PR around the committed choice; no further compile needed unless the procedure changes.
- `wiki/nixos-platform/skeleton-sops-pattern.md` (new) — the three-step "why eval succeeds without real encryption" pattern (path literal + validateSopsFiles=false + no eval-time decryption). Generalises beyond this project.
