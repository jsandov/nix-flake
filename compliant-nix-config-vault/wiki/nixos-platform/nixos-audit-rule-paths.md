# NixOS Audit Rule Paths

The path mapping that auditd rules, FIM rules, and sudo `secure_path` entries must use on NixOS. Traditional Linux FHS paths (`/usr/bin`, `/usr/sbin`, `/sbin`, `/usr/lib`) are empty or nonexistent on NixOS — any rule that references them monitors nothing and silently fails.

## Path Mapping

| Traditional Linux | NixOS equivalent | What lives there |
|---|---|---|
| `/usr/bin/` | `/run/current-system/sw/bin/` | Standard system binaries |
| `/usr/sbin/` | `/run/current-system/sw/sbin/` | System admin binaries |
| `/sbin/` | `/run/current-system/sw/bin/` | (NixOS consolidates into sw/bin) |
| `/usr/bin/sudo` | `/run/wrappers/bin/sudo` | **Setuid wrappers** |
| `/usr/bin/su` | `/run/wrappers/bin/su` | Setuid wrappers |
| `/usr/bin/passwd` | `/run/wrappers/bin/passwd` | Setuid wrappers |
| `/usr/bin/mount` | `/run/wrappers/bin/mount` | Setuid wrappers |
| `/usr/lib/` | per-package Nix store paths | Library files (no unified `/usr/lib`) |

**The critical split:** setuid-wrapped commands live under `/run/wrappers/bin/`, not `/run/current-system/sw/bin/`. NixOS generates per-system setuid wrappers at activation time because the Nix store is mounted read-only and can't hold setuid bits safely. Auditing `sudo` or `su` at a non-wrapper path audits nothing.

## Concrete Examples

### Before (broken — silently monitors nothing)

```nix
security.auditd.rules = [
  "-w /usr/bin/sudo -p x -k privilege_escalation"
  "-w /usr/bin/su -p x -k privilege_escalation"
  "-w /sbin/modprobe -p x -k kernel_modules"
  "-w /sbin/insmod -p x -k kernel_modules"
];
```

### After (correct)

```nix
security.auditd.rules = [
  "-w /run/wrappers/bin/sudo -p x -k privilege_escalation"
  "-w /run/wrappers/bin/su -p x -k privilege_escalation"
  "-w /run/current-system/sw/bin/modprobe -p x -k kernel_modules"
  "-w /run/current-system/sw/bin/insmod -p x -k kernel_modules"
];
```

## AIDE / FIM

AIDE rules follow the same mapping. See [[../shared-controls/canonical-config|canonical.aidePaths]] for the committed project list. The canonical list:

- `/run/current-system/sw/bin` — monitors every system binary change
- `/run/current-system/sw/sbin` — monitors admin binaries
- `/etc` — system configuration
- `/boot` — bootloader + kernel
- `/nix/var/nix/profiles/system` — the NixOS generation symlink (detects rebuilds)

## sudo `secure_path`

```nix
security.sudo.extraConfig = ''
  Defaults secure_path="/run/wrappers/bin:/run/current-system/sw/bin"
'';
```

Never include `/usr/bin` or `/sbin` — they're empty, and `sudo` will fall through to PATH resolution.

## CI Lint Pattern

The repo enforces this in two layers (see [[../architecture/ci-gate]]):

1. **Broad lint on `modules/` + `hosts/`** — any `/usr/bin/`, `/usr/sbin/`, or `/sbin/` reference fails the build. Appropriate because real module code has no legitimate reason to name those paths.
2. **Narrow lint on `docs/`** — matches only the quoted audit-rule syntax `"-w /usr/bin/...`. PRD prose legitimately names the FHS paths in warnings, "DO NOT monitor" bullets, shebangs, and example audit-log entries; the broad lint would false-positive on all of those.

The narrow regex is exactly:

```
"-w /(usr/bin|usr/sbin|sbin)/
```

Lint-design rule surfaced here: **use the broadest regex that does not false-positive.** For module code, that's any FHS path. For PRD prose, that's the quoted audit-rule shape. See [[../review-findings/lessons-learned]] entry 27 for the two-layer pattern's general form.

## Related Gotchas

- [[nixos-gotchas#2-nixos-paths-are-different]] — general NixOS path structure.
- [[nixos-gotchas#14-module-system-forces-all-or-nothing-for-options-vs-config]] — unrelated but adjacent.

## Key Takeaways

- Setuid wrappers: `/run/wrappers/bin/`. Everything else: `/run/current-system/sw/bin/`.
- AIDE, auditd, and sudo `secure_path` all follow the same mapping.
- The project's canonical AIDE path list lives in [[../shared-controls/canonical-config|canonical.aidePaths]].
- CI enforces the mapping with a two-layer lint (broad for code, narrow for docs).
