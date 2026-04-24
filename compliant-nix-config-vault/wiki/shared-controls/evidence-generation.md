# Evidence Generation

Automated compliance evidence collection via a single shared snapshotter that every framework module (HIPAA, PCI, HITRUST, STIG-evidence, NIST) plugs into. Shipped in ARCH-10 as `modules/audit-and-aide/evidence.nix`.

## Why one framework, not five

Every compliance target (HIPAA §164.308(a)(1)(ii)(D), PCI 10.7 + 12.10.1, HITRUST 06.e, NIST AU-6, STIG audit review) requires periodic evidence capture. Implementing five separate timers and five output conventions means five bugs, five prune policies, five auditor-facing directory layouts. One snapshotter, one schema, five framework modules consume it. See also [[shared-controls-overview]] on the "implement once, satisfy many" principle.

## Option surface

```nix
services.complianceEvidence = {
  enable           = true;          # mkDefault true when audit-and-aide is imported
  cadence          = "weekly";      # systemd OnCalendar expression
  directory        = "/var/lib/compliance-evidence";
  retainSnapshots  = 52;            # count-based prune; ~1 year weekly
  runOnActivation  = true;          # also snapshot on every nixos-rebuild switch
  collectors       = { /* attrsOf submodule { description, command, outputFile } */ };
};
```

- `directory` is declared in `canonical.tmpfilesRules` at `0750 root:root` — do not redeclare.
- `enable` is set to `lib.mkDefault true` by the `audit-and-aide` aggregator, not by `evidence.nix` itself (placing it inside `config = mkIf cfg.enable …` would be circular — see [[../review-findings/lessons-learned#39-aggregator-style-default-nix-for-module-families]]).

## The collectors extension point

`collectors` is an `attrsOf (submodule { description, command, outputFile })`. Framework modules register their own entries rather than editing this module — keeps framework-specific knowledge out of the shared plumbing and preserves the ARCH-16 module-boundary rule.

```nix
# In a future modules/hipaa-evidence/default.nix
services.complianceEvidence.collectors.phiAccessLog = {
  description = "PHI access-audit extract for the HIPAA snapshot (§164.312(b)).";
  command     = "${pkgs.audit}/bin/ausearch -k phi-access -ts today";
  outputFile  = "phi-access.txt";
};
```

Overriding a core collector requires `lib.mkForce` — makes the intent loud. This pattern is the canonical Nix shape for "downstream modules contribute rows" ([[../review-findings/lessons-learned#40-extension-point-options-attrsof-submodule]]).

## v1 default collector set (13 + manifest)

| Key | Command | Output | What it proves |
|---|---|---|---|
| `passwd` | `getent passwd` | `getent-passwd.txt` | Account-state reproducibility (AC-2) |
| `group` | `getent group` | `getent-group.txt` | Group-state reproducibility |
| `nftRuleset` | `nft list ruleset` | `nft-ruleset.txt` | Firewall state of record (NIST SC-7, PCI 1.2) |
| `auditctlRules` | `auditctl -l` | `auditctl-rules.txt` | Loaded audit rules (AU-2, HIPAA §164.312(b)) |
| `systemClosure` | `nix-store --query --requisites /run/current-system \| head -n 500` | `system-closure-top500.txt` | Top 500 store-path requisites (CM-8) |
| `nixosGenerations` | `nixos-rebuild list-generations` | `nixos-generations.txt` | Rollback inventory (CM-2) |
| `sshdConfig` | `sshd -T` | `sshd-effective.txt` | Effective SSH config (IA-2) |
| `cryptsetupStatus` | `cryptsetup status` per `/dev/mapper/*` | `cryptsetup-status.txt` | LUKS proof (SC-28, HIPAA §164.312(a)(2)(iv), PCI 3.5) |
| `nixStoreVerify` | `nix-store --verify` | `nix-store-verify.txt` | Store integrity (SI-7); `--check-contents` rejected as prohibitively slow |
| `flakeMetadata` | `nix flake metadata --json \|\| true` | `flake-metadata.json` | Flake input pins with SHAs (SR-4) |
| `nixosVersion` | `nixos-version` | `nixos-version.txt` | System identity (CM-8) |
| `nixInfo` | `nix-info -m` | `nix-info.txt` | Host facts / toolchain context |
| `resolvedSettings` | `cat /etc/compliance/resolved-settings.yaml` | `resolved-settings.yaml` | Canonical decision table at snapshot time (ties to [[canonical-config]]) |
| *(post-step)* | `sha256sum` of every non-manifest file | `manifest.sha256` | Tamper seal — NIST AU-9, HIPAA §164.312(c)(1) |

## Cadence — weekly plus on-rebuild

Two triggers, deliberately redundant:

- **Weekly** via `systemd.timers.compliance-evidence-snapshot` — `OnCalendar=weekly`, `Persistent=true` (catches up if the host was off), 15-minute randomised delay to avoid colliding with other weekly jobs. Satisfies PCI 10.7 / HITRUST 06.e minimum cadence with headroom.
- **On every `nixos-rebuild switch`** via `system.activationScripts.complianceEvidenceOnRebuild`. The more interesting half: every rebuild produces a snapshot correlated with the auditd `nixos-rebuild` watch key from [[../nixos-platform/auditd-module-pattern|INFRA-04]]. An auditor can pair the `/nix/var/nix/profiles/system` auditd record with a timestamped snapshot showing exactly what state the system moved into.

Snapshot directories are named `YYYYMMDD-HHMMSS/` (UTC). Snapshots sort lexicographically by time; `retainSnapshots` prunes the oldest N.

## Self-describing snapshots

`environment.etc."compliance/resolved-settings.yaml".source = ../../docs/resolved-settings.yaml;` wires the ARCH-04 YAML onto the target. The `resolvedSettings` collector copies it into every snapshot so the evidence is self-describing — an auditor seeing a rule decision can verify which version of the conflict-resolution table produced it. Without this, snapshot interpretation would require cross-referencing a running system.

## Tamper seal

`manifest.sha256` is written as the last step of each run and contains one SHA-256 per collector output, sorted for deterministic diffs. An auditor verifies integrity after-the-fact with `sha256sum -c manifest.sha256`. Gives the NIST AU-9 / HIPAA §164.312(c)(1) integrity property without the repository-size problem of Git-committing every snapshot.

## Retention

Default `retainSnapshots = 52` ≈ one year of weekly runs — meets PCI 1-year minimum. HIPAA covered-entity deployments should override to `312` (52 × 6 years). Revisit once [[../architecture/ci-gate|INFRA-08]] lands central log forwarding — remote retention may obviate multi-year local storage.

## What this unblocks

- **ARCH-17** (acceptance-criteria test harness): consumes `/var/lib/compliance-evidence/` as the canonical location where acceptance checks read live state.
- **Future HIPAA / PCI / HITRUST framework modules:** register their own collectors via `services.complianceEvidence.collectors.<name>` — no edits to `evidence.nix` required.
- **ARCH-18** (framework drift + quarterly review dumps): piggybacks on the same snapshotter.
- **INFRA-08** (TLS log forwarding): auditd-log extract collector will register here once the source-of-truth decision is settled (local journald vs central collector).

## Rejected alternatives

- `OnCalendar=daily` — too noisy; PCI minimum is quarterly.
- Write to `/var/log/compliance-evidence/` — `/var/log` is line-oriented journald territory. Evidence is structured state; `/var/lib/compliance-evidence/` is the FHS-correct location.
- Git-commit every snapshot — volume blows up over multi-year retention. SHA-256 manifest is what NIST AU-9 / HIPAA §164.312(c)(1) actually require.
- Separate top-level `modules/compliance-evidence/` — audit and evidence are one NIST control family (AU); splitting disconnects the activation-hook / auditd-watch correlation.
- Per-collector systemd service unit — overkill for sub-second shell invocations.
- `nix-store --verify --check-contents` — minutes to hours on a GPU-driver-laden store.

## Key Takeaways

- Evidence generation is fully automated — no manual collection.
- One framework across NIST, HIPAA, PCI DSS, HITRUST, and STIG — framework modules extend, they don't duplicate.
- `services.complianceEvidence.collectors` is the canonical [[../review-findings/lessons-learned#40-extension-point-options-attrsof-submodule|attrsOf-submodule extension point]]; future framework modules contribute entries.
- Activation-script + weekly-timer duality pairs every rebuild with a snapshot *and* gives auditor-facing regularity.
- `manifest.sha256` per snapshot is the tamper seal; includes every collector output.
- Snapshots are self-describing: each one carries the `resolved-settings.yaml` active at that moment.
- Evidence directory should be included in backup schedule.
