# Skeleton Secrets Pattern

How to let `nix flake check` and `nix eval` succeed on a repo that declares sops-nix secrets but has no real encrypted content yet. The pattern keeps [[../architecture/ci-gate]] meaningful on day one — before any age key has been provisioned — without watering down the runtime security model.

## The Problem

[[../shared-controls/secrets-management|sops-nix]] is the committed secrets mechanism. The skeleton commit has to:

1. Declare every secret with owner/mode/path so consumer modules can start referencing `config.sops.secrets.<name>.path` immediately.
2. Still evaluate cleanly in CI, which has no age key and no real encrypted file.
3. Not ship a design that a real deployment can "forget" to harden — the skeleton-only relaxations must be obviously transitional.

## Three Settings That Make It Work

| Setting | Value (skeleton) | Value (real deploy) | Why |
|---|---|---|---|
| `sops.defaultSopsFile` | `../../secrets/secrets.enc.yaml` (path literal, file exists but is plain-text) | Same path, sops-encrypted body | Nix path literals must exist at eval; contents are not inspected until activation. |
| `sops.validateSopsFiles` | `false` | `true` | Disables the eval-time format check that would otherwise reject the plain-text placeholder. Real deployments re-enable. |
| `sops.age.generateKey` | `false` | `false` (always) | Never auto-generate. Age private key entering the Nix store defeats the whole threat model. |

Two additional structural rules make the pattern safe:

- **Decryption never runs at eval.** sops-nix reads the file and decrypts at systemd activation, not when Nix evaluates the module tree. CI's `nix eval .drvPath` gets as far as "what derivation would build this system" and stops — no decryption attempted.
- **Secret `path` overrides are strings**, not Nix path literals. `path = "/etc/ssh/ssh_host_ed25519_key"` is interpreted at activation; it does not need to exist at eval.

## The Placeholder File

Ship `secrets/secrets.enc.yaml` with a plain-YAML body explaining its transitional role:

```yaml
# Placeholder — replace with a real sops-encrypted file before any deployment.
#
# Purpose: this file exists so `nix flake check` / `nix eval` can resolve
# `sops.defaultSopsFile = ../secrets/secrets.enc.yaml` at evaluation time.
# `sops.validateSopsFiles = false` disables format validation, so this
# plain YAML is accepted.

_placeholder: "skeleton; replaced by sops-encrypted content on first deploy"
```

## Deployment Hardening Checklist

Before a real deployment, flip back:

- [ ] Encrypt the file body: `sops secrets/secrets.enc.yaml` (same path; body replaced).
- [ ] Set `sops.validateSopsFiles = true` in the host config.
- [ ] Provision `/var/lib/sops-nix/key.txt` with the age private key via physical console or one-shot SSH.
- [ ] Verify activation: `sudo nixos-rebuild switch` should now decrypt secrets into `/run/secrets/*` at boot.

## Why This is Better Than the Alternatives

- **Conditional module enable (`lib.mkIf config.enable ...`)** — works, but a host can forget to flip the switch. The placeholder-file pattern forces the deployer to think about secrets because the file is visible in the repo root.
- **Stubbing out `sops.secrets`** — every downstream module that reads `config.sops.secrets.<name>.path` would eval-fail, blocking foundation work on unrelated modules.
- **Branching the module tree** — shipping two flake outputs (with/without secrets) doubles the CI matrix for no gain.

The placeholder approach keeps the module tree identical between skeleton and deployment, and the "what needs to change" list lives in this article and in the placeholder file header.

## Generalises Beyond Sops

The three-element pattern — "file literal that needs to exist + eval-time validation toggle + no eval-time side effects" — shows up whenever a module wires a real security primitive that cannot be exercised in CI:

- LUKS: declare devices + keys without requiring the device to be present.
- TLS ACME: declare cert configuration without requiring an ACME challenge to succeed at eval.
- Hardware-scoped modules (GPU, TPM): declare options without requiring the hardware.

Each case uses the same split: "stuff that must exist at eval" (path literals, file references) vs "stuff that runs at activation" (decryption, mount, ACME challenge).

## Key Takeaways

- `sops.defaultSopsFile` is a Nix path literal — the file must exist at eval, but its content is not inspected until activation.
- `sops.validateSopsFiles = false` is a skeleton-only escape hatch; real deployments re-enable.
- Age private keys never live in the Nix store — `sops.age.generateKey = false` is mandatory, not optional.
- The pattern keeps the module tree identical between skeleton and deployment, so no code has to change when secrets go live.
- The same "path-exists + validation-off + no-eval-side-effects" split applies to other security primitives that cannot run in CI.
