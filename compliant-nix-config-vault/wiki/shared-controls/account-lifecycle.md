# Account Lifecycle

`modules/accounts/default.nix` owns interactive operator identity on the compliance-mapped NixOS AI server. Shipped in ARCH-11 (PR #49) as the first real downstream consumer of the [[evidence-generation|ARCH-10 evidence-collector extension point]].

## Scope

- Names interactive operators (v1 surface: a single `adminUser` submodule).
- Pins them to key-based SSH login — `hashedPassword = "!"` idiom; no valid crypt hash ever matches.
- Registers a quarterly access-review collector with `services.complianceEvidence.collectors.accessReview`.
- Does **not** own policy values — password length, lockout, session timeout, MFA scope stay in [[canonical-config|`canonical.auth.*`]].
- Does **not** redeclare `users.mutableUsers` — already owned by `stig-baseline` from `canonical.nixosOptions.usersMutableUsers`.

## Option surface

```nix
security.accounts = {
  adminUser = {
    name = "admin";
    description = "Primary operator — key-based login only.";
    authorizedKeys = [ "ssh-ed25519 AAAA... operator@host" ];
    groups = [ "wheel" ];           # default
  };
  accessReviewEnable = true;         # default; gates the collector registration
};
```

The `adminUser.name` should match `canonical.ssh.allowUsers`; INFRA-07 is the natural place to add a cross-module assertion.

## Why `hashedPassword = "!"`

`"!"` is an invalid password hash — `crypt(3)` will never produce it for any input. Equivalent to disabling password auth, but without leaving a NULL field that some audit tooling misreads as "passwordless." Matches the project stance that all remote admin access is SSH + MFA (`canonical.auth.mfaScope = "all-remote-admin"`). There is no password to rotate and no password to leak.

## Why the SSH public key lives in the host, not sops-nix

Public keys are public. Anyone can read them off the wire during SSH connection setup. Encrypting them via [[secrets-management|sops-nix]] adds a decrypt roundtrip without security value and couples account declaration to secrets-lifecycle plumbing. SSH **private** keys belong on the operator's workstation, never in the flake.

## Access-review collector

Registered at module eval via the [[evidence-generation#the-collectors-extension-point|ARCH-10 attrsOf-submodule extension point]]. No separate systemd timer — the [[evidence-generation#cadence—weekly-plus-on-rebuild|ARCH-10 snapshot framework IS the cadence]]. Every weekly snapshot and every `nixos-rebuild switch` emits `access-review.txt` inside the snapshot directory.

Contents of the report:

- `getent passwd <admin>` — declared account is actually realised.
- `ssh-keygen -lf` fingerprint of every `authorizedKeys` entry.
- `chage -l <admin>` — password-aging inventory (tracks unused-account drift).
- A `lib.generators.toPretty` snapshot of the `canonical.auth` values in force at config time — policy-of-record.

The SHA-256 manifest that closes each snapshot covers `access-review.txt` automatically, so tamper-evidence comes for free.

## Why this module retires `users.allowNoPasswordLogin`

The skeleton carried `users.allowNoPasswordLogin = lib.mkDefault true` inside `stig-baseline` to satisfy NixOS's "root password or a wheel user with keys" assertion when no admin was declared. Now that `modules/accounts/` declares a wheel user with `authorizedKeys`, the assertion is satisfied structurally. ARCH-11 (PR #49) removed the escape hatch; attempting to bring it back would be a regression.

## Patterns confirmed

- **First downstream consumer of the evidence-collector extension point.** Validates [[../review-findings/lessons-learned#40-extension-point-options-attrsof-submodule|lesson 40]] at scale — framework modules register rows without editing the shared module.
- **Identity in `accounts`, policy in `canonical`.** Same split that governs every other control family. The access-review collector **embeds the canonical policy snapshot in its output**, making the separation visible to auditors without forcing them to cross-reference files.
- **No separate timer for review cadence.** [[../review-findings/lessons-learned#41-activation-script-timer-duality-for-compliance-tasks|Lesson 41]] played in reverse: when a shared snapshot framework exists, new compliance work piggybacks on its cadence rather than declaring its own.

## Rejected alternatives

- Store SSH public keys in sops-nix — public, no encryption value.
- Separate `account-review-report` systemd timer — ARCH-10 framework is the cadence.
- Module named `users` or `identity` — `accounts` mirrors the TODO id and the ISO 27001 control-family naming.
- Declare `users.mutableUsers` here — already owned by `stig-baseline` from canonical; two modules declaring the same value is duplication without benefit.

## Open follow-ups

- **Multi-admin scenarios.** V1 is a single `adminUser` submodule. Extending to `listOf (submodule ...)` is deferred until a second operator actually exists.
- **Canonical-to-host name coupling.** Admin user name defaults to `admin` and `canonical.ssh.allowUsers = [ "admin" ]`. If a host renames, both must move together. Enforcement belongs in INFRA-07.
- **SSH key rotation enforcement.** Cadence declared in `canonical`; the module does not enforce expiry. Future work, probably paired with the access-review collector growing a "key older than N days" warning.
- **Placeholder ed25519 key.** The skeleton ships a `SKELETON…PLACEHOLDER` key in `hosts/ai-server/default.nix`. Must be replaced with the real operator key before any real deploy.

## Control-family citations

- NIST AC-2 (Account Management), AC-2(3) (Disable Inactive Accounts), IA-2, IA-5.
- HIPAA §164.308(a)(3)(ii)(B-C), §164.308(a)(4)(ii)(B).
- PCI DSS 7, 8.1, 8.2.
- HITRUST 01.* (Access Control domain).
- STIG primary Account Management findings.

## Key Takeaways

- `modules/accounts/` is the identity module; `canonical.auth` is the policy module.
- `hashedPassword = "!"` is the right idiom for key-only admin accounts.
- SSH public keys live inline in the host — not in sops-nix.
- Access review runs as an ARCH-10 collector, not a standalone timer.
- Existence of this module is what lets `users.allowNoPasswordLogin` be removed from `stig-baseline`.
