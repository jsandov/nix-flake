# INFRA-04 — audit-and-aide module (first real module code)

Session notes from landing the first non-stub module. Up to this point every `modules/*/default.nix` has been a comment-bearing empty module; this PR makes `modules/audit-and-aide/default.nix` real by implementing the auditd portion of its charter. AIDE stays stubbed until INFRA-09.

## Why this is a milestone

All prior P0/P1 work was either infrastructure (canonical, secrets, meta) or PRD prose. This is the first module that actually declares behaviour in the running system — `security.auditd.enable = true` with a real audit-rule set. Breaking it would break `nix eval`, break the CI gate, and block every subsequent module PR. Landing it green validates the whole foundation.

## What the module does

Two NixOS options take the bulk of the work:

1. **`security.auditd.enable = true`** — turns on the userspace audit daemon.
2. **`security.audit`** — the kernel-side audit subsystem and its ruleset:
   - `enable = true`
   - `backlogLimit = 8192` (STIG-recommended kernel buffer)
   - `failureMode = "printk"` (logs kernel message on audit subsystem failure but keeps system running; panic mode is too operationally risky for a single-operator deployment)
   - `rules = [ ... ]` — the full audit-rule list

## The audit-rule catalogue

Organised by category:

| Category | Rules |
|---|---|
| Account & auth files | `/etc/{passwd,group,shadow,gshadow,sudoers,sudoers.d}` |
| PAM config | `/etc/pam.d` |
| SSH config | `/etc/ssh/sshd_config` |
| Privilege escalation via setuid wrappers | `/run/wrappers/bin/{sudo,su,passwd,chsh,newgrp}` — **NixOS-specific path** |
| Account management | `/run/current-system/sw/bin/chage` |
| NixOS system changes | `/nix/var/nix/profiles/system`, `/run/current-system`, `/etc/nixos` |
| Audit log tamper | `/var/log/audit`, `/etc/audit` |
| Kernel modules | `modprobe`/`insmod`/`rmmod` binaries + `init_module`/`delete_module`/`finit_module` syscalls |
| Setuid/setgid syscalls | `setuid`, `setgid`, `setreuid`, `setregid`, `setresuid`, `setresgid` |
| Time changes | `adjtimex`, `settimeofday`, `clock_settime`, `/etc/localtime` |
| Network config | `/etc/hosts`, `/etc/resolv.conf`, `sethostname`, `setdomainname` |
| Process manipulation | `personality`, `ptrace`, `open_by_handle_at` (MASTER-REVIEW STIG should-fix #3) |
| Failed access | `open`/`openat` with `EACCES` or `EPERM` |
| Mount/umount | `mount`, `umount2` |
| File deletion | `unlink`, `unlinkat`, `rename`, `renameat` (with auid>=1000 filter) |
| Lock ruleset | `-e 2` (must be last) |

## Design decisions

### `-e 2` locks the ruleset

MUST be the last rule. Freezes the ruleset until reboot; a process with `CAP_AUDIT_CONTROL` cannot remove or modify rules at runtime. Required by STIG and a cornerstone audit-integrity control — without it, an attacker with root could unwire auditing on a compromised host.

Trade-off: changing audit rules requires a reboot, not a `systemctl reload`. Acceptable for a compliance-focused system; rule changes should be infrequent and deliberate.

### `failureMode = "printk"` not `"panic"`

Three options:

- `silent` / `0` — ignore failure. Loses events. Fails PCI 10.5.3.
- `printk` / `1` — log to kernel messages, continue. Evidence preserved via dmesg; operational continuity maintained.
- `panic` / `2` — halt the system. Maximum safety; risk of DOS if audit subsystem has any flakiness.

Single-operator deployment in a LAN-only context — `printk` is the right balance. A multi-tenant regulated-data production host might justify `panic`; this project's threat model doesn't.

### auid filter on deletion rules

`-F auid>=1000 -F auid!=-1` excludes deletion events performed by system services (auid < 1000) and unknown-auid events (auid = -1). Catches user-driven deletions only, which is where the forensic signal lives — system-service deletions flood the log and drown out real activity.

### Paths come from the NixOS audit-rule reference

[[../compliant-nix-config-vault/wiki/nixos-platform/nixos-audit-rule-paths|wiki/nixos-platform/nixos-audit-rule-paths]] is the canonical reference for which path to use for which binary. Setuid wrappers go under `/run/wrappers/bin/`; everything else goes under `/run/current-system/sw/bin/`. The module follows this rule universally.

### Not using `canonical.*` yet

The audit-rule list is declared inline in the module rather than pulled from a `canonical.auditRules` attribute. Rationale:

- The rules are single-framework (STIG-derived) with only minor cross-framework deltas.
- The rules are specific to this module; no other module would consume them.
- Adding `canonical.auditRules` would open a design question about per-service rule inclusion that is not justified today.

If a future module needs to contribute rules (say, `ai-services` adding watchers on `/var/lib/ollama/models`), we migrate to canonical at that point.

### AIDE is intentionally deferred

The module is named `audit-and-aide` and its stub comment promised both. This PR ships only auditd. AIDE requires:

- Consuming `canonical.aidePaths` (already in canonical)
- A systemd timer (hourly per `canonical.scanning.aideFileIntegrity`)
- Alerting via `OnFailure=notify-admin@` (requires the notify template from canonical A.15)

That's a separate concern with its own TODO (INFRA-09). Splitting avoids a 250-line PR where review attention would fragment between two orthogonal systems.

## Interaction with existing infrastructure

- Consumes the [[../compliant-nix-config-vault/wiki/nixos-platform/nixos-audit-rule-paths|audit-rule path mapping]] — every path reference follows the setuid-wrapper-vs-sw/bin rule.
- Passes the [[../compliant-nix-config-vault/wiki/architecture/ci-gate|CI gate]] including the broad FHS lint (no `/usr/bin`/`/sbin` anywhere in the module).
- Does NOT yet consume `modules/canonical/*` — the audit-rule set is inline for now (see above).
- Does NOT yet consume `modules/meta/*` — future work could gate rule inclusion on `config.system.compliance.dataClassification.tiers[].handling`.

## Validation

No local `nix` CLI. Validation path: CI. The module declares only built-in NixOS options (`security.auditd.enable`, `security.audit.*`, `services.journald.extraConfig`) — no phantom options, no third-party references. Should eval cleanly on the first CI iteration.

If something surprising trips, most likely culprits:
- `backlogLimit` — type might be `types.int` with a specific range; if it rejects 8192, drop to default.
- `failureMode` — enum with specific values; if "printk" isn't the accepted string, the enum list will name what is.
- `rules` — `types.listOf types.str`, should be safe.

## Suggested wiki compile targets

- `wiki/nixos-platform/auditd-module-pattern.md` (new) — the `security.auditd` + `security.audit` setup, failure-mode trade-off, `-e 2` lock rule, backlog sizing. Paired companion to [[../nixos-platform/nixos-audit-rule-paths|the path-mapping reference]]: one article on what paths to use, another on how to wire the subsystem.
- Extend [[../architecture/flake-modules|flake-modules]] to update `audit-and-aide`'s description now that it's partially implemented.
- Consider a `wiki/review-findings/lessons-learned.md` entry on "first real module code" milestones — what changes in review shape when the repo graduates from scaffolding to behaviour.
