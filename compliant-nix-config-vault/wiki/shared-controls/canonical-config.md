# Canonical Configuration

The single-source-of-truth mechanism for every setting whose resolution is driven by cross-framework compliance requirements. Two paired artifacts, one runtime + one audit, with an enforced agreement contract.

## The Problem It Solves

The [[review-findings/master-review|master review]] called out Systemic Issue #1 — the seven framework PRDs had already diverged on values like `MaxRetentionSec`, SSH cipher lists, password policy, firewall rules, and tmpfiles modes *before any real code existed*. Without a single source of truth, every framework module PR would compound the divergence.

## Two Paired Artifacts

| Artifact | Shape | Audience | Role |
|---|---|---|---|
| `modules/canonical/default.nix` | NixOS module declaring `options.canonical.*` with typed defaults | Nix evaluator + downstream modules | **Runtime** source of truth |
| `docs/resolved-settings.yaml` | Flat YAML rows with provenance metadata | Auditors, PR reviewers | **Audit** source of truth |

They must agree on every value. They carry different *metadata*:

| Field | `canonical.nix` | `resolved-settings.yaml` |
|---|---|---|
| Value | ✓ as `mkOption` default | ✓ as `value:` |
| Type | ✓ via `types.*` | implicit from YAML shape |
| Driving framework | ✗ | ✓ |
| Rejected values + reasons | ✗ | ✓ |
| Rationale link back to PRD | shared intro comment only | ✓ per row |

## Why a NixOS Module, Not a Plain Attrset

Two shapes were evaluated for the runtime source:

- **Shape A — NixOS module declaring `options.canonical.*`.** Downstream modules read `config.canonical.*`; overrides go through `lib.mkForce`; values show up in `nixos-option` introspection; type-checked on every CI pass.
- **Shape B — Plain `.nix` attrset imported by each consumer.** Simpler but bypasses the module system. No type checking, no priority-aware overrides, no way for a host to rebind one value without forking the file.

Shape A won. Every downstream module (`stig-baseline`, `lan-only-network`, `ai-services`, etc.) gets `config.canonical.*` for free once the module is composed into the `nixosSystem` — no explicit import needed per module.

## Three Type Patterns

Appendix A content falls into three shapes; each gets a different Nix type:

| Content shape | Nix type | Example |
|---|---|---|
| Grouped settings with distinct semantics | `types.submodule { options = { ... }; }` | `canonical.ssh.*`, `canonical.systemdHardening.*` |
| Flat key-value tables (all same value type) | `types.attrsOf types.str` | `canonical.patching`, `canonical.scanning` |
| Ordered records | `types.listOf (types.submodule { ... })` | `canonical.tmpfilesRules`, `canonical.aidePaths` |

Submodule-typed fields catch typos in consumers at eval time. Attrset-typed tables keep adding a new cadence entry as a one-line change.

## Two-List Carve-Out Pattern

Some settings split by service class. The canonical example is `MemoryDenyWriteExecute` — required on non-CUDA services, forbidden on CUDA services because [[nixos-gotchas#5-cuda-breaks-memorydenywriteexecute|CUDA's JIT needs W+X memory]]. Encode this as two explicit lists:

```nix
memoryDenyWriteExecuteServices = [ "agent-runner" "ai-api" ];
memoryDenyWriteExecuteExempt   = [ "ollama" ];
```

Downstream modules check membership and emit the directive accordingly. More ergonomic than a per-service attrset and auditable via grep.

## Symbolic Values

Some canonical values are intentionally symbolic, not literal:

- `sshListen = "lan"` — the host module resolves "lan" to the deployment's LAN interface address at deploy time. The canonical module must not hardcode a deployment-specific IP.
- `journalMaxRetention = "365day"` — consumers translate this to the concrete NixOS option form their module needs (`MaxRetentionSec`, `OnCalendar`, etc.).

The rule: canonical preserves Appendix A's concrete value when it is directly consumable; it preserves the symbolic form when the same value feeds multiple consumers that each need to translate.

## Override Ergonomics

A host that genuinely needs a different canonical value does:

```nix
canonical.auth.lockoutThreshold = lib.mkForce 10;
```

`lib.mkForce` is deliberately required. The canonical module uses `mkOption { default = ...; }` which sets the default at `lib.mkOptionDefault` priority. Any plain assignment at a host still resolves against the default. A deliberate override must be loud.

## What the Canonical Module Does NOT Do

- **It does not USE the values.** `services.openssh.settings.KexAlgorithms = config.canonical.ssh.kexAlgorithms` is the job of the `stig-baseline` module (or whichever module owns SSH). Canonical is an option declaration, not a consumer.
- **It does not resolve host-specific deployment values.** Symbols stay symbolic.
- **It does not overlap with `modules/meta/default.nix`** (ARCH-08). Canonical holds Appendix A settings (quantitative). Meta will hold threat model, data classification, tenancy (qualitative).

## The YAML Schema

Every row in `docs/resolved-settings.yaml`:

```yaml
- id: A.N.slug             # Stable identifier — never renumber.
  section: A.N Section     # Matches Appendix A subsection heading.
  setting: Human name      # One-line description.
  canonical_path: canonical.foo.bar   # Dotted path into canonical.nix.
  value: <literal>         # YAML scalar/list/map matching the Nix default.
  driving_frameworks: [STIG, NIST]
  consensus: true|false    # If true, omit rejected_values.
  rejected_values:         # Only for consensus: false.
    - value: <literal>
      proposed_by: <framework module or section>
      rejection_reason: >
        Why this value was not chosen — specific to this proposal.
  rationale_link: docs/prd/prd.md#a4-...
```

Field notes:

- **`id`** is stable. Once assigned, never renumber. Superseded rows get marked; the id is not reused.
- **`value`** shape must match the canonical default's shape — flat list if canonical is `types.listOf types.str`, list of records if canonical is `types.listOf (types.submodule {...})`.
- **`rejection_reason`** is the highest-leverage field for PR review. Keep it specific. "PCI wanted 12, but STIG is stricter at 15" is the target density.
- **`rationale_link`** points back to Appendix A — the narrative explanation behind the resolution.

## The Agreement Contract

Canonical and YAML must agree on every value. Until ARCH-17 (acceptance-criteria test harness) lands:

- Every PR that changes `canonical.nix` must update the matching YAML row in the same commit.
- Every PR that changes a `value:` in the YAML must update the canonical default in the same commit.
- PR review checks both.

ARCH-17 will parse the YAML, walk `config.canonical.*`, and fail the build on disagreement. Machine-enforced agreement is the eventual state; human discipline is the interim.

## Consumer Contract (for Future Module PRs)

When a framework module needs a value:

1. Find the row in `docs/resolved-settings.yaml` with the matching setting.
2. Read the `canonical_path` field.
3. In the module, assign from `config.<canonical_path>` — never inline a literal.
4. If no row exists, add one first (YAML + canonical.nix in the same PR).

This is what [[../architecture/ci-gate]] + ARCH-16 boundary lints will enforce. For now, PR review enforces it.

## Key Takeaways

- Two artifacts: `modules/canonical/default.nix` (runtime) + `docs/resolved-settings.yaml` (audit). They must agree on values.
- Three type patterns map to three Appendix A content shapes: submodule for grouped, attrsOf for flat tables, listOf submodule for records.
- `lib.mkForce` is the only legal override mechanism — default priority is intentional.
- Canonical declares; does not consume. Consumption is the job of framework modules.
- Every downstream module reads `config.canonical.*`; never inlines a literal.
- Rejection reasons in the YAML are the most valuable field for future PR review — they let "can we revisit X?" proposals land or get blocked by the original rationale.
