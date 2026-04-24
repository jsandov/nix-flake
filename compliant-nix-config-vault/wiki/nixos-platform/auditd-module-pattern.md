# auditd Module Pattern

How to wire `security.auditd` + `security.audit` on NixOS for a compliance baseline. Pairs with [[nixos-audit-rule-paths|the audit-rule path mapping]] — that article tells you *which* paths; this one tells you *how* to set the subsystem up.

## Three Options That Matter

```nix
security.auditd.enable = true;
security.audit = {
  enable = true;
  backlogLimit = 8192;
  failureMode = "printk";
  rules = [ /* see nixos-audit-rule-paths for path choices */ ];
};
```

### `backlogLimit`

Kernel audit buffer size. Default is 64; STIG recommends 8192 to survive burst loads without event loss. Higher values trade kernel memory for resilience. 8192 is conservative; 32768 is defensible for high-throughput systems.

### `failureMode`

Three values, each a different risk posture:

| Value | Behaviour on audit failure | When to pick |
|---|---|---|
| `silent` | Ignores; keeps running. Events lost. | **Never** for a compliance system — fails PCI 10.5.3. |
| `printk` | Logs kernel message via dmesg; keeps running. | Single-operator / workstation deployments. Evidence preserved; operational continuity maintained. |
| `panic` | Halts the system. | Multi-tenant regulated-data production. Maximal safety; risk of DOS if audit subsystem is flaky. |

This project uses `printk` because the single-operator threat model doesn't justify the panic-DOS risk. A production multi-tenant deployment would flip to `panic`.

### The `-e 2` Final Rule

MUST be the last entry in `rules`. Freezes the ruleset until reboot: a process with `CAP_AUDIT_CONTROL` cannot remove or modify audit rules at runtime. Required by STIG and a cornerstone audit-integrity control — without it, an attacker with root could unwire auditing on a compromised host.

Trade-off: changing audit rules requires a reboot, not `systemctl reload`. Acceptable for compliance-focused systems where rule changes are infrequent and deliberate.

## Persistent Journal

```nix
services.journald.extraConfig = ''
  Storage=persistent
  Compress=yes
'';
```

Audit events survive reboot for offline forensic review. Distinct from `/var/log/audit/audit.log`; both are read for cross-referenced evidence.

## `auid` Filters on Deletion Rules

```nix
"-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=-1 -k file-deletion"
```

Two filters together:
- `auid>=1000` — excludes system-service deletions (UID < 1000 for daemons).
- `auid!=-1` — excludes events where `auid` is unset (very early boot, some kernel code paths).

Net: user-driven deletions only. Without these filters, the log floods with system-service deletions and drowns out forensic signal.

## When to Extract Rules to `canonical`

This project keeps rules inline in `modules/audit-and-aide/auditd.nix` rather than pulling from `canonical.auditRules`. (The `audit-and-aide` aggregator `default.nix` now imports `./auditd.nix` + `./evidence.nix`; see [[../shared-controls/evidence-generation]] for the split.) The rationale (which applies generally):

- Rules are STIG-derived with only minor cross-framework deltas.
- Rules are specific to one module — no other module would consume them.
- Adding `canonical.auditRules` would open design questions about per-service rule inclusion that aren't justified today.

**Rule of thumb:** migrate to canonical when a second module needs to contribute rules (say, an `ai-services` module adding `-w /var/lib/ollama/models` watchers). Until then, inline.

## Relation to Other Modules

- [[../shared-controls/canonical-config|canonical.aidePaths]] — consumed by AIDE (INFRA-09 future), not by auditd.
- [[../shared-controls/canonical-config|canonical.tmpfilesRules]] — consumed by `systemd.tmpfiles.rules`, a separate control. Audit rules use `-w <path>` which is its own mechanism.
- [[nixos-audit-rule-paths|NixOS audit-rule paths]] — every path in `rules` follows the setuid-wrapper-vs-sw/bin mapping.

## First-Real-Module Milestone

INFRA-04 (the PR that enabled auditd) was the first non-stub module to land in the repo. Before it, every module directory held only an ownership-comment stub. Landing real behaviour in a module validates the whole foundation — canonical + meta + secrets + CI lints all survive contact with a real `security.*` option tree.

If you're implementing the equivalent milestone on another compliance-as-code NixOS project:
- Start with the module whose correctness is most verifiable (auditd has simple, dumpable output via `auditctl -l`).
- Use NixOS's built-in options only; avoid third-party module imports until the foundation is proven.
- Have CI run `nix eval` on the toplevel drvPath — the module's presence will break or not break the whole tree.

## Key Takeaways

- `security.auditd.enable` + `security.audit.enable` + typed `rules` list is the complete interface.
- `backlogLimit = 8192`, `failureMode = "printk"` (workstation) or `"panic"` (multi-tenant production).
- `-e 2` as final rule locks the ruleset until reboot; required by STIG.
- `auid>=1000 -F auid!=-1` on deletion rules filters out system-service noise.
- Inline rules first; extract to canonical only when a second consumer appears.
- Path choices follow [[nixos-audit-rule-paths]].
