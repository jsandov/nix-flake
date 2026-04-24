# ARCH-10 — Evidence generation framework

Session note for the shared evidence-snapshot module. First cross-cutting runtime service that every future framework module (HIPAA, PCI, HITRUST, STIG-evidence, NIST) will plug into instead of reinventing.

## What shipped

- New module: `modules/audit-and-aide/evidence.nix` — imported from the `audit-and-aide` aggregator alongside the existing `auditd.nix`. Single import site keeps the audit family (NIST AU) together.
- `modules/audit-and-aide/default.nix` converted to a thin aggregator (`imports = [ ./auditd.nix ./evidence.nix ]` + `services.complianceEvidence.enable = lib.mkDefault true`). The old body moved verbatim into `auditd.nix`.
- Option namespace: `services.complianceEvidence.*`.
  - `enable` (bool; default-enabled via `mkDefault true` in the aggregator — opt-out by `lib.mkForce false` at host level).
  - `cadence` (str, default `"weekly"`). Systemd `OnCalendar` expression for the timer.
  - `directory` (path, default `/var/lib/compliance-evidence`). FHS-correct; declared in `canonical.tmpfilesRules` as `0750 root root`.
  - `retainSnapshots` (positive int, default `52`). Count-based pruning; ≈1 year of weekly runs.
  - `collectors` (attrsOf submodule `{ description, command, outputFile }`) — extension point for framework modules.
  - `runOnActivation` (bool, default `true`). Gates the `nixos-rebuild switch` hook.
- Timer + service: `systemd.timers.compliance-evidence-snapshot` (wantedBy=timers.target, `Persistent=true`, `RandomizedDelaySec=15min`) + `systemd.services.compliance-evidence-snapshot` (`Type=oneshot`, `User=root`).
- Activation hook: `system.activationScripts.complianceEvidenceOnRebuild` invokes the same snapshotter with `|| true`.
- `environment.etc."compliance/resolved-settings.yaml".source = ../../docs/resolved-settings.yaml` — the conflict-resolution table is now on-target and copied into every snapshot.
- Default collector set: 13 core collectors wired at module-eval time (list below). Each snapshot run also writes `manifest.sha256` covering every non-manifest file in the directory.
- Snapshot binary is added to `environment.systemPackages` so an operator can run `compliance-evidence-snapshot` ad-hoc.

## Why this design

- **Shared framework, not per-framework evidence scripts.** Every framework (HIPAA §164.308(a)(1)(ii)(D), PCI 10.7 + 12.10.1, HITRUST 06.e, NIST AU-6, STIG audit review) requires periodic evidence capture. Five separate timers + five output conventions would mean five bugs, five prune policies, five auditor-facing directory layouts. One snapshotter, one schema, five framework modules consume it.
- **Weekly + on-rebuild.** Weekly satisfies PCI 10.7 / HITRUST 06.e minimum cadence with headroom. On-rebuild is the more interesting half: every `nixos-rebuild switch` now produces a snapshot correlated with the auditd `nixos-rebuild` watch key from INFRA-04. An auditor can pair the `/nix/var/nix/profiles/system` auditd record with a timestamped snapshot showing exactly what state the system moved into.
- **`collectors` as an extension point, not hard-coded.** Framework modules must be able to register their own collectors without editing this module. HIPAA will want a PHI-access log extract; PCI will want cardholder-scope listings; HITRUST will want a control-maturity dump. Hard-coding them here would centralise framework-specific knowledge in the wrong module and violate the module-boundary rule flagged for ARCH-16. `types.attrsOf (types.submodule …)` is the canonical Nix shape for "downstream modules contribute rows."
- **SHA-256 manifest per snapshot.** Every file is hashed; `manifest.sha256` is written last and is part of the snapshot. Gives tamper-evidence without Git overhead — an auditor can re-run `sha256sum -c manifest.sha256` and prove no file was edited post-generation. Meets NIST AU-9 integrity and HIPAA §164.312(c)(1) integrity-controls framing.
- **Copy `resolved-settings.yaml` into each snapshot.** A snapshot must be self-describing. Without the resolved-settings file, an auditor seeing a rule decision has no way to verify which version of the conflict-resolution table produced it. Pinning the YAML into the snapshot ties the evidence to the canonical decisions at that moment.

## Collectors in the v1 default set

13 collectors written at eval time. Each maps to a concrete auditor question:

- `passwd` — `getent passwd` → `getent-passwd.txt`. Account-state reproducibility.
- `group` — `getent group` → `getent-group.txt`. Group-state reproducibility.
- `nftRuleset` — `nft list ruleset` → `nft-ruleset.txt`. Firewall state of record (NIST SC-7, PCI 1.2).
- `auditctlRules` — `auditctl -l` → `auditctl-rules.txt`. Loaded audit-rule inventory (NIST AU-2, HIPAA §164.312(b)).
- `systemClosure` — `nix-store --query --requisites /run/current-system | head -n 500` → `system-closure-top500.txt`. Top 500 store-path requisites; full closure is reproducible from flake lock.
- `nixosGenerations` — `nixos-rebuild list-generations` → `nixos-generations.txt`. Rollback inventory.
- `sshdConfig` — `sshd -T` → `sshd-effective.txt`. Effective SSH config (resolved settings actually in force).
- `cryptsetupStatus` — per-device `cryptsetup status` across `/dev/mapper/*` → `cryptsetup-status.txt`. Encryption-at-rest proof for HIPAA §164.312(a)(2)(iv), PCI 3.5.
- `nixStoreVerify` — `nix-store --verify` (no `--check-contents`) → `nix-store-verify.txt`. Store integrity via signature / hash-name; `--check-contents` rejected as prohibitively slow on a store with GPU drivers and model weights.
- `flakeMetadata` — `nix flake metadata --json 2>&1 || true` → `flake-metadata.json`. Flake input pins with SHAs; best-effort because the flake may not live at the working directory used by the service.
- `nixosVersion` — `nixos-version` → `nixos-version.txt`. Channel / revision / codename.
- `nixInfo` — `nix-info -m` → `nix-info.txt`. Platform + channel dump.
- `resolvedSettings` — `cat /etc/compliance/resolved-settings.yaml` → `resolved-settings.yaml`. Canonical decision table at snapshot time.
- **Manifest (post-step, not a collector):** `sha256sum` of every non-manifest file → `manifest.sha256`. Tamper seal.

## Patterns confirmed / introduced

- **Extension-point options** via `types.attrsOf (types.submodule { options = { … }; })`. Canonical shape for "downstream modules contribute to a shared pipeline." First load-bearing appearance is here; HIPAA/PCI/HITRUST evidence hooks will follow.
- **Activation-script + timer duality** — compliance tasks that must run on change AND on cadence. Activation gives correlation with the actor who triggered the switch; timer gives auditor-facing regularity. Pattern will recur for ARCH-11 (account review), ARCH-15 (CVE scans), ARCH-18 (framework drift).
- **`environment.etc.<name>.source` from a flake-tracked docs file** — shipping a repo document onto the target for runtime consumption. Works cleanly because `resolved-settings.yaml` lives under `docs/` and is read by eval. Avoids drift between source-of-truth YAML and on-target copy.
- **Aggregator-style `default.nix`** — splitting a module family into `imports = [ ./a.nix ./b.nix ]` keeps each concern's file small. First instance in this repo; the pattern will repeat when INFRA-09 (AIDE) lands as a third submodule of `audit-and-aide`.
- **`pkgs.writeShellApplication` over raw `pkgs.writeShellScript`** — the former adds `set -euo pipefail`, shellcheck, and a `runtimeInputs` PATH-only sandbox. Right default for any real compliance action.

## What this unblocks

- **ARCH-17** (acceptance-criteria test harness) — consumes `/var/lib/compliance-evidence/` to assert prd.md §10 acceptance criteria against live output.
- **Future HIPAA / PCI / HITRUST framework modules** — register their own collectors via `services.complianceEvidence.collectors.<name>` without editing this module.
- **ARCH-18** (framework drift + quarterly review dumps) — piggybacks on the same snapshotter. Drift collector and quarterly-access-review collector are just two more entries.
- **INFRA-08** (TLS log forwarding) — an auditd-log extract collector can be registered here once INFRA-08 decides where log extracts originate.

## Rejected alternatives

- **`OnCalendar=daily`.** Too noisy for a single-operator host; PCI/HITRUST minimum is quarterly. Weekly is the sweet spot: fresh enough for a compile-on-demand audit touchpoint, sparse enough that a year of snapshots is ~52 dated directories plus however many rebuilds happened.
- **Write to `/var/log/compliance-evidence/`.** `/var/log` is journald/syslog territory and is line-oriented. Evidence is structured state (YAML, JSON, text dumps). `/var/lib/compliance-evidence/` is the FHS-correct location and is already declared in `canonical.tmpfilesRules`.
- **Git-commit every snapshot.** Evidence volume grows rapidly (hundreds of files × weekly × multi-year). Tamper-evidence via per-snapshot SHA-256 manifest gives the verification property without the repository-size problem, and is what NIST AU-9 and HIPAA §164.312(c)(1) actually ask for.
- **Separate top-level `modules/compliance-evidence/` module outside `audit-and-aide/`.** Audit and evidence are one NIST control family (AU); splitting adds a module boundary without capability benefit and disconnects the activation-script-on-rebuild correlation from the auditd `nixos-rebuild` watch key that makes it valuable.
- **Per-collector systemd service unit.** Overkill. Collectors are sub-second shell invocations; one oneshot service that loops over `cfg.collectors` is simpler and produces a single failure mode the operator already knows how to read.
- **`--check-contents` on `nix-store --verify`.** Re-hashes every file in the store; minutes to hours on an AI host. The signature / hash-name check is what compliance frameworks actually require.

## Open follow-ups

- **Auditd-log extract collector** — defer until INFRA-08 decides whether extracts come from the local journald or from the central collector. Wiring it now would bake in a source-of-truth assumption that may reverse.
- **Retention policy.** `retainSnapshots = 52` meets PCI 1-year minimum. HIPAA can require up to 6 years depending on covered-entity type; covered-entity deployments should override to `312` (52 × 6). Revisit when INFRA-08 lands — central log forwarding may obviate the need to retain multi-year local snapshots.
- **Rebuild-vs-timer race.** A `nixos-rebuild switch` triggered at the exact moment of a weekly timer firing would run the snapshotter twice concurrently. Not observed in practice; if it shows up, a lock file (`/run/compliance-evidence.lock`) or a `ConditionPathExists=!…` on the service unit are the straightforward fixes.
- **`nixos-rebuild` / `nixos-version` via PATH, not `pkgs.*`.** Neither ships as a standalone `pkgs.<name>` in `nixos-24.11`, so the script prepends `/run/current-system/sw/bin` to `PATH`. Reasonable for a root-only service; revisit if `pkgs.nixos-rebuild` lands in a later nixpkgs bump.
- **Collector-failure handling.** Current behaviour: a failing collector writes its stderr to the output file and the service continues. Auditor sees the error in-context. Consider promoting to `StandardOutput=journal+console` so failures also surface in the operator's normal log feed.
- **`services.complianceEvidence.enable` defaulted via the aggregator `default.nix`.** Placing `mkDefault true` inside `evidence.nix` itself would sit inside `config = mkIf cfg.enable { … }`, which is circular. The aggregator-side default works; if `audit-and-aide` is ever imported without the aggregator (e.g., a consumer imports `evidence.nix` directly), the operator must set `enable = true` explicitly.
