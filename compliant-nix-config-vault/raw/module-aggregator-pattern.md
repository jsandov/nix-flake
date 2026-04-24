# Module aggregator pattern

Raw note for the compile. Source of the pattern: ARCH-10 split of `modules/audit-and-aide/default.nix` into `auditd.nix` + `evidence.nix`, with the original `default.nix` shrunk to a thin aggregator. Currently unique to `audit-and-aide/`; expected to repeat for INFRA-09 (AIDE as third submodule) and potentially for any future multi-concern module family.

## What shipped (reference implementation)

```nix
# modules/audit-and-aide/default.nix
{ lib, ... }:
{
  # <comment: family scope + control-family citations>

  imports = [
    ./auditd.nix
    ./evidence.nix
  ];

  # Default-enable the cross-submodule service here. mkDefault (not
  # mkForce) so an operator can still override at the host level.
  services.complianceEvidence.enable = lib.mkDefault true;
}
```

- `auditd.nix` — INFRA-04; comprehensive kernel audit rules. Standalone concern.
- `evidence.nix` — ARCH-10; shared `services.complianceEvidence.*` framework. Standalone concern.
- `default.nix` — aggregator; orchestrates the two and owns family-wide defaults.

## Why split

1. **Concern size.** `auditd.nix` was ~140 lines of audit rules; `evidence.nix` is ~340 lines of option declarations + snapshot machinery. A 500-line single file fights the reader.
2. **Independent iteration.** Auditd rules change on STIG releases; evidence collectors change on framework-module shipping cadence. Separate files = cleaner bisect.
3. **Control-family attribution stays intact.** The aggregator comment names the whole audit family (NIST AU-2 / AU-3 / AU-6 / AU-12, PCI 10.x, HITRUST 06.e); each submodule comment names its narrower citations.
4. **Future-proofing.** INFRA-09 AIDE lands as a third file next to `auditd.nix` + `evidence.nix` — no big restructure needed.

## Where family-wide defaults live — aggregator, not submodule

```nix
# WRONG — circular
# evidence.nix
config = mkIf cfg.enable {
  services.complianceEvidence.enable = lib.mkDefault true;   # never reached
  ...
};
```

Placing the `mkDefault` inside `evidence.nix` itself would sit **inside** `config = mkIf cfg.enable { … }`. The module is gated on the very value it's trying to default — circular. The aggregator (which runs unconditionally) is the right owner.

```nix
# RIGHT — aggregator-owned default
# default.nix
{ lib, ... }:
{
  imports = [ ./auditd.nix ./evidence.nix ];
  services.complianceEvidence.enable = lib.mkDefault true;
}
```

## When to use

- A module family has **multiple concerns** that ship at different times (INFRA-04 → ARCH-10 → INFRA-09 all landed or will land in the `audit-and-aide/` family).
- A single file would exceed ~300 lines or would mix option-declaration code with option-consumption code.
- Family members share a cross-submodule enable default or a common assertion block.
- The module's comment block is already using control-family headers — a sign the concerns deserve their own files.

## When NOT to use

- Single-concern modules. `stig-baseline/default.nix` is one concern (OS hardening from `canonical.*`) even though it's long; splitting would fragment a coherent boot-integrity + kernel-hardening + sysctl narrative.
- Two small files that could live as one. Don't split a 50-line module into 25 + 25.
- Flake-level composition. Keep `flake.nix` with all modules listed in one place; the aggregator pattern is for `modules/<name>/` subtrees, not for the flake output.

## Relationship to ARCH-16 boundary rules

The aggregator pattern is **compatible with** the ARCH-16 module-boundary rule ("each option is declared by exactly one module"). The submodules each own their options; the aggregator owns cross-submodule defaults only. If two submodules start declaring the same option, that's an ARCH-16 violation — the aggregator does not fix it by merging.

## Control-family attribution in the aggregator comment

Recommended template:

```
# <family> — aggregator module.
#
# Splits into focused submodules so each concern can evolve independently:
#   - a.nix : <concern A, primary TODO id>
#   - b.nix : <concern B, primary TODO id>
#
# <future submodule note, e.g. "INFRA-09 will add aide.nix as a third submodule.">
#
# Control families: <NIST / HIPAA / PCI / HITRUST / STIG rollup across all submodules>.
```

## Expected future instances

1. **INFRA-09 AIDE** → third submodule `modules/audit-and-aide/aide.nix`. Registers an `aideDaily` collector with `services.complianceEvidence.collectors`. Aggregator gains a corresponding import + possibly a default for `services.aide.enable`.
2. Any module that grows to own both a typed-options surface **and** a systemd-service implementation could split along that line (e.g. `options.nix` + `service.nix`) — but the audit-and-aide split is by **concern**, not by options-vs-config, which reads better in practice.

## Rejected alternative — one big module

Keeping `modules/audit-and-aide/default.nix` as a single 500-line file was considered. Rejected because:

- Each module PR touches only one concern; the diff noise on unrelated concerns was high.
- The `audit` and `evidence` halves cite different control families — keeping them separate keeps the citations accurate without forcing a single huge comment block.
- Future AIDE work would have pushed the file to 700+ lines, past the point where a file browser helps.

## Open follow-ups

- Whether to extract `services.complianceEvidence.*` option namespace into a sibling module (e.g. `modules/compliance-evidence/`) instead of a submodule of `audit-and-aide/`. Rejected in ARCH-10 because audit and evidence are one NIST family (AU); revisit if the framework gains consumers outside the audit family.
- Aggregator `imports` ordering — currently alphabetical-ish by filename. No dependency constraint; document the ordering choice so future submodule additions don't reorder for aesthetic reasons.
