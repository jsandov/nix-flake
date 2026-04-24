# Module aggregator pattern

When a module family grows beyond one concern, split it into submodules and shrink `default.nix` to a thin aggregator. Pattern first landed in ARCH-10's split of `modules/audit-and-aide/default.nix` into `auditd.nix` (INFRA-04) + `evidence.nix` (ARCH-10); will repeat when INFRA-09 adds AIDE as a third submodule.

## Reference shape

```nix
# modules/audit-and-aide/default.nix
{ lib, ... }:
{
  # audit-and-aide — aggregator module.
  # Splits into focused submodules:
  #   - auditd.nix   : kernel audit rules (INFRA-04)
  #   - evidence.nix : compliance-evidence framework (ARCH-10)
  # INFRA-09 will add aide.nix as a third submodule.
  #
  # Control families: NIST AU-2 / AU-3 / AU-6 / AU-12; HIPAA §164.312(b);
  # PCI 10.2 / 10.3 / 10.7; HITRUST 06.e; STIG primary audit baseline.

  imports = [
    ./auditd.nix
    ./evidence.nix
  ];

  services.complianceEvidence.enable = lib.mkDefault true;
}
```

- Each submodule is a standalone concern — its own comment block, control citations, and option surface.
- The aggregator owns cross-submodule defaults and the family-wide comment block.
- No options are declared in the aggregator.

## Why split

- **Concern size.** A ~500-line module fights the reader; splitting keeps each file browseable and bisect-friendly.
- **Independent iteration.** auditd rules change on STIG releases; evidence collectors change per framework-module shipping cadence. Separate files = cleaner diffs per PR.
- **Control-family attribution stays accurate.** The family-rollup lives in the aggregator; each submodule cites only its own controls.
- **Future-proofing.** Adding a third concern (AIDE) is a new file next to the others, not a restructure.

## Where cross-submodule defaults live — aggregator, not submodule

Placing the `mkDefault` inside the submodule is circular:

```nix
# evidence.nix
config = mkIf cfg.enable {
  services.complianceEvidence.enable = lib.mkDefault true;   # never reached
  ...
};
```

The submodule is gated on the very value it's trying to default. The aggregator (which runs unconditionally) is the right owner of that default. See [[../review-findings/lessons-learned#39-aggregator-style-default-nix-for-module-families|lesson 39]] for the worked example.

## When to use the pattern

- A module family ships multiple concerns with different cadences (INFRA-04 → ARCH-10 → INFRA-09 in `audit-and-aide/`).
- A single file would exceed ~300 lines or mix option-declaration with option-consumption.
- Family members share a cross-submodule enable default or a family-level assertion block.
- The comment block is already organised by control family — a sign the concerns deserve their own files.

## When NOT to use it

- **Single-concern modules.** `stig-baseline/default.nix` is one long but coherent narrative (canonical consumption + Secure Boot priority dance). Splitting would fragment it.
- **Two small files.** Don't split a 50-line module into 25 + 25.
- **Flake-level composition.** `flake.nix` keeps the full module list in one place. The aggregator pattern is for `modules/<name>/` subtrees only.

## Relationship to ARCH-16 boundary rules

The pattern is **compatible with** the ARCH-16 module-boundary rule ("each option is declared by exactly one module"). Submodules own their own options; the aggregator owns only cross-submodule defaults. Two submodules declaring the same option is an ARCH-16 violation — the aggregator does not paper over it by merging.

## Expected next instance

**INFRA-09 AIDE** — third submodule `modules/audit-and-aide/aide.nix`. Consumes `canonical.aidePaths`; registers a file-integrity collector with [[../shared-controls/evidence-generation|services.complianceEvidence.collectors]]; aggregator gains one `./aide.nix` import and possibly a `services.aide.enable = lib.mkDefault true;` default. Pattern holds without modification.

## Rejected alternatives

- **Keep one big `default.nix`.** Diff noise across unrelated concerns; comment blocks get unwieldy when two concerns cite different control families; future AIDE work would push the file past ~700 lines.
- **Split along options-vs-config axis** (e.g. `options.nix` + `service.nix`). Rejected — audit and evidence are different **concerns**, not different **phases of declaring the same concern**. A concern-based split reads better in practice.
- **Extract `evidence.nix` into a sibling top-level module** (`modules/compliance-evidence/`). Rejected in ARCH-10 because audit and evidence are one NIST control family (AU); the split would disconnect the activation-hook / auditd-watch-key correlation that makes the evidence framework valuable. Revisit only if the framework gains consumers outside the audit family.

## Key Takeaways

- Split a module family when concerns have independent cadences or the single file exceeds ~300 lines — not purely on length.
- Aggregator owns cross-submodule defaults; submodules own their own option declarations.
- Placing a cross-submodule `mkDefault` inside a `config = mkIf cfg.enable { … }` is circular; use the aggregator.
- Control-family citations stay accurate when each submodule names its own controls and the aggregator names the rollup.
- Compatible with ARCH-16 module-boundary rules; not a workaround for them.
