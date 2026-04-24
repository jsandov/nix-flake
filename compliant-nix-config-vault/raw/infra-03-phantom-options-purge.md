# INFRA-03 — Purge phantom / deprecated NixOS options from PRD snippets

Session notes from implementing INFRA-03. MASTER-REVIEW Systemic Issue #2 catalogued ~17 Nix snippets across the PRDs that would fail evaluation or misbehave at runtime. Many were already flagged elsewhere (ARCH-05 fixed sops-nix stuff; ARCH-06 fixed audit paths; AI-* TODOs own Ollama-specific bugs). This sweep covers the OS-baseline phantom options that don't fit anywhere else.

## What got fixed

### `environment.etc."login.defs".text` / `.source` overrides

Two snippets overrode `/etc/login.defs` directly. Both conflict with the shadow package that NixOS ships — the shadow package writes login.defs itself, and any `environment.etc."login.defs".text` override fights it. Some fields get dropped silently; some PAM modules read the unintended value.

NixOS 24.11+ ships `security.loginDefs.settings.*` as typed structured options that merge cleanly with the shadow-package defaults. All overrides should go through this attrset.

| File | Pattern | Fix |
|---|---|---|
| `prd-hitrust.md:271` | `environment.etc."login.defs".text = ''...''` | `security.loginDefs.settings = { PASS_MAX_DAYS = 60; ... };` (also corrected HITRUST's 365-day value down to canonical 60) |
| `prd-stig-disa.md:691` | `environment.etc."login.defs" = { source = lib.mkForce (pkgs.writeText ...); }` | `security.loginDefs.settings = { UMASK = "077"; ... };` |

Note the type shape: strings stay strings (`"077"`, `"yes"`, `"SHA512"`), integers drop the quotes (`60`, `1000`). `SHA_CRYPT_ROUNDS` split into `SHA_CRYPT_MIN_ROUNDS` + `SHA_CRYPT_MAX_ROUNDS` because that's the structured option shape.

### `services.xserver.videoDrivers` without `hardware.nvidia`

MASTER-REVIEW flagged this as "set without enabling xserver or hardware.nvidia" in `prd-nist-800-53.md`. The actual snippet today does include a proper `hardware.nvidia` block, but the videoDrivers line without context invited the historical mis-reading. Added a comment explaining that:

1. `hardware.nvidia.package` is the load-bearing declaration.
2. `services.xserver.videoDrivers = [ "nvidia" ]` is honoured even when `services.xserver.enable = false`.
3. The line is kept for explicit documentation of driver choice; a future simplification could drop it if `hardware.nvidia.package` alone proves sufficient for the consuming module.

No code change — annotation only. If a future CI evaluation finds the line harmful, we remove it in a follow-up.

### `SSH Protocol 2 only` prose in prd-hitrust.md

The bullet said "SSH Protocol 2 only (NixOS OpenSSH defaults to Protocol 2)." An implementer reading this could reasonably assume there is a `Protocol` directive to configure. There isn't — OpenSSH 7.6+ removed the `Protocol` directive entirely (Protocol 1 dropped, Protocol 2 is the only remaining behaviour). Setting `Protocol = 2` in `services.openssh.extraConfig` breaks sshd startup on NixOS.

Rewrote the bullet to spell this out: the requirement is implicit in the OpenSSH version; there is no option to configure; do not set `Protocol` at all.

## What's already correctly documented and didn't need changes

- **`security.protectKernelImage`** — only appears in MASTER-REVIEW as a historical finding. Not in any current PRD snippet.
- **`pkgs.pam`** — only in an explanatory comment (`prd-stig-disa.md:364`: "NOTE: pkgs.pam does not exist in nixpkgs..."). Correct warning.
- **`Protocol = 2`** in `prd.md` Appendix A.4 — explicitly a "Do not set" table entry. Correct.
- **`fips=yes` in OpenSSL** — `prd-stig-disa.md` has multiple warning blocks and a commented-out snippet with explicit "DO NOT" warnings. Correct.
- **`swapDevices.*.encrypted`** — covered by `docs/resolved-settings.yaml` A.9 row with rejection reason pointing at NixOS 23.11+ removal.
- **`ssl_ciphers HIGH:!aNULL:!MD5:!RC4`** — the offending pattern is not in any current PRD snippet; current snippets use proper AEAD cipher lists.
- **Ollama-specific phantoms** (`OLLAMA_HOST = "0.0.0.0:..."`, `MemoryDenyWriteExecute=true` on CUDA, `WatchdogSec=300`, `OLLAMA_NOPRUNE=1`) — owned by AI-01/02/06/07 P0 TODOs; explicitly out of INFRA-03 scope.
- **Audit rule FHS paths** — owned by ARCH-06; lint in place.

## Why no new lint for INFRA-03

The ARCH-03 broad lint (modules/hosts grep) and the ARCH-06 narrow lint (docs/ audit-rule syntax) cover most regression vectors. A lint for INFRA-03 would need to target specific patterns like `environment\.etc\."login\.defs"\.(text|source)` — but the replacement prose legitimately names the pattern in comments ("DO NOT use environment.etc..."). Distinguishing a real usage from a "do not use" comment in grep is fragile.

The PRD now names the correct option (`security.loginDefs.settings`). A future module PR that uses `environment.etc."login.defs"` instead would be caught by PR review (the pattern is a red flag to any reviewer familiar with NixOS shadow-package interactions) and by the ARCH-03 broad lint once the code lands in `modules/`.

Lesson worth capturing: **some TODOs are one-shot sweeps that don't benefit from a lint.** The decision is: can the lint distinguish real usage from descriptive prose without false-positives? For INFRA-03, no. For ARCH-06, yes (the quoted `"-w /usr/bin/...` pattern is unambiguous).

## Suggested wiki compile targets

- `wiki/nixos-platform/nixos-gotchas.md` — extend with a new entry: "`environment.etc.\"login.defs\"` overrides conflict with shadow package; use `security.loginDefs.settings.*` instead." Current gotcha #4 mentions deprecated SSH options but not login.defs.
- `wiki/architecture/ci-gate.md` — consider adding a sidebar about "when a lint is right vs when a sweep is right" with the INFRA-03 one-shot call-out.
