# ARCH-06 — FHS-path sweep of PRD prose + tightened CI lint

Session notes from implementing ARCH-06. The TODO had two parts; one was preempted by ARCH-03, the other needed a manual sweep plus a narrower lint.

## What this TODO actually was

"Strip `/usr/bin`, `/sbin`, `/usr/sbin` everywhere" — the real work split three ways:

1. **Module and host code** — covered by the ARCH-03 CI lint (`grep -rnE '/(usr/bin|usr/sbin|sbin)/' modules/ hosts/`). As of this TODO, there was zero hit in those trees because no real module code had landed yet. The lint keeps working on every future PR.
2. **PRD audit-rule snippets** — actual broken auditd rules inside Nix snippets in `docs/prd/`. These would ship wrong if a future module PR copy-pasted them. Three rules needed fixing.
3. **PRD descriptive prose** — legitimate mentions of `/usr/bin` in warnings, `"DO NOT monitor"` notes, shebangs, MASTER-REVIEW's historical findings, and Appendix A.12's explicit allowlist. These stay.

## The three broken rules

All three were quoted audit-rule strings with FHS paths that do not exist on NixOS:

| File | Before | After |
|---|---|---|
| `prd-hitrust.md:1235` | `"-w /usr/bin/sudo -p x -k privilege_escalation"` | `"-w /run/wrappers/bin/sudo -p x -k privilege_escalation"` |
| `prd-hitrust.md:1236` | `"-w /usr/bin/su -p x -k privilege_escalation"` | `"-w /run/wrappers/bin/su -p x -k privilege_escalation"` |
| `prd-hitrust.md:1249` | `"-w /sbin/modprobe -p x -k kernel_modules"` | `"-w /run/current-system/sw/bin/modprobe -p x -k kernel_modules"` |
| `prd-hitrust.md:1250` | `"-w /sbin/insmod -p x -k kernel_modules"` | `"-w /run/current-system/sw/bin/insmod -p x -k kernel_modules"` |
| `prd-nist-800-53.md:977-978` | `"-w /sbin/{insmod,modprobe} -p x -k module-load"` | `"-w /run/current-system/sw/bin/{insmod,modprobe} -p x -k module-load"` |

Path mapping rule:

- Setuid-wrapped commands (`sudo`, `su`, `passwd`, `mount`, etc.) → `/run/wrappers/bin/`
- Every other system command → `/run/current-system/sw/bin/`

## Tightened CI lint

The original ARCH-03 lint covered `modules/` and `hosts/`. PRD files were excluded because grep would fire on the legitimate descriptive references. Two-lint design:

```yaml
# Lint 1 — broad sweep of real config code
- name: Legacy FHS path lint — module and host code (ARCH-06)
  run: |
    if grep -rnE '/(usr/bin|usr/sbin|sbin)/' modules/ hosts/ 2>/dev/null; then exit 1; fi

# Lint 2 — narrow sweep of PRD audit-rule syntax
- name: Legacy FHS path lint — PRD audit-rule syntax (ARCH-06)
  run: |
    if grep -rnE '"-w /(usr/bin|usr/sbin|sbin)/' docs/ 2>/dev/null; then exit 1; fi
```

The narrow regex matches only quoted auditd-rule syntax — `"-w /usr/bin/...`. That's the exact shape of the three broken rules. Descriptive prose like "these paths do not exist on NixOS", `#!/usr/bin/env bash`, `exe="/usr/bin/passwd"` in an example audit log entry, and bullet-list warnings all pass.

## What was left alone (and why)

- `MASTER-REVIEW.md` lines 62, 161, 198, 243 — historical record of what was broken before the sweep; not a current bug.
- `prd.md` §A.12 — explicit allowlist of NixOS AIDE paths + "DO NOT monitor" warning about FHS paths. The warning names the FHS paths so a reader can recognise them in legacy documentation.
- `prd-pci-dss.md` lines 901, 1272, 1368 — illustrative audit-log record and two explanatory notes.
- `prd-stig-disa.md` lines 972, 1025, 1412–1420 — NixOS-path notes and correct rules.
- Shebangs (`#!/usr/bin/env bash`) in `prd-stig-disa.md:2155, 2555` and `prd-ai-governance.md:1348` — `/usr/bin/env` exists on NixOS via systemd's compatibility shim. Shebangs work.

## Process meta-lesson

ARCH-06 was easy because ARCH-03 already existed. The CI lint made the "is there anything broken right now?" question a five-second grep. The "will this regress?" question was already answered by the existing workflow. All I had to do was:

1. Extend the lint regex to cover PRD audit-rule syntax.
2. Fix the three violations the new lint would have caught.
3. Confirm with `grep` that nothing else matched the narrower pattern.

This reinforces lessons 24 + 25 from the bring-up: **prefer lints over sweeps; narrow regexes let a lint cover content where a broader one would false-positive.**

## Suggested wiki compile targets

- `wiki/nixos-platform/nixos-audit-rule-paths.md` (new) — the setuid-wrapper vs sw/bin mapping, plus the narrow-regex CI lint pattern for PRD-style content. Small but useful reference; [[nixos-gotchas]] #2 touches the general gotcha but not the specific path mapping.
- `wiki/review-findings/lessons-learned.md` — consider adding an entry about the two-layer lint pattern (broad for code, narrow for docs).
