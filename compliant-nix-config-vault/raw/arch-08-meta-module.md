# ARCH-08 — Meta module: threat model, data classification, tenancy

Session notes from codifying project-level qualitative metadata as NixOS options. Complements [[../shared-controls/canonical-config|canonical]] (quantitative Appendix A values) with the qualitative "shape" of the system.

## Why separate from canonical

Canonical holds cross-framework-resolved values — settings where multiple frameworks proposed different numbers and the project resolved to the strictest (log retention, SSH ciphers, password policy). Meta holds values that are not cross-framework resolutions at all: who are the adversaries? how is data classified? is the host single- or multi-tenant?

These questions have answers that shape which controls downstream modules actually enable. An `agent-sandbox` module reads `config.system.compliance.dataClassification.tiers` to know what "Restricted" means and gate on it; an `ai-services` module reads `config.system.compliance.tenancy.mode` to decide whether to enforce per-tenant isolation controls that don't exist in the single-tenant default.

Keeping meta separate from canonical preserves the audit narrative: canonical is the "how we resolved conflicts" log; meta is the "what we designed for" log.

## Three options

All under `options.system.compliance.*` with typed submodules and safe defaults.

### `threatModel`

Three sub-options:

- `adversaries` — list of enum values. In-scope adversary types. Defaults to insider-unprivileged, external-LAN-unauthorised, supply-chain-compromise, malicious-model-upstream, prompt-injection-via-user-input.
- `crownJewels` — list of strings. Free-form because framework-specific labels vary (ePHI vs PII vs CHD vs "model weights"); an enum would force premature categorisation. Default includes the seven crown-jewel classes named across the PRDs.
- `outOfScope` — list of enum values. Explicitly accepted out-of-scope attacks. Documenting prevents scope creep. Defaults to physical-access, nation-state-actor, rubber-hose-cryptanalysis.

The enum on `adversaries` + `outOfScope` but free-form `crownJewels` is a deliberate choice — new adversary types come from a small finite list (rogue agent? insider with GPU access?) while crown-jewel names proliferate with the business context.

### `dataClassification`

Two sub-options:

- `scheme` — single-value enum `four-tier-public-internal-sensitive-restricted`. Single-value-enum pattern again (see canonical.firewall.backend): declares intent that this IS the scheme, and a future PR that tries to replace it fails at eval with a clear error.
- `tiers` — list of submodules, each with `name`, `level`, `examples`, `handling`. Four tiers preloaded: Public / Internal / Sensitive / Restricted, with examples + handling requirements pulled from prd.md Appendix A-adjacent prose and the HIPAA PRD's ePHI flow.

The `handling` field is a short prose description — not machine-parsed today, but will be consumed by evidence generation (ARCH-10) to emit "this is how tier N data is handled" as audit evidence without duplicating the prose.

### `tenancy`

Two sub-options:

- `mode` — enum `single-tenant | multi-tenant`. Default single-tenant. This is the most consequential option in meta — changing it to multi-tenant invalidates the sops recipient model, the agent-sandbox UID scheme, the model-registry layout, and the audit-stream architecture.
- `rationale` — string. Short prose explaining the choice. Becomes evidence for assessors who ask "how do you isolate tenants?" — the answer is fundamentally different per mode, and the string documents the choice.

## What this module does NOT do

- **It does not enforce anything.** Like canonical, meta declares; downstream modules consume. An agent-sandbox module gating on `config.system.compliance.dataClassification.tiers` can refuse to handle Restricted data without encryption; that enforcement is the agent-sandbox module's job, not meta's.
- **It does not resolve the human-gated open decision.** Tenancy defaults to single-tenant because that's the project's designed-for mode. The open decision ("confirm single-tenant explicitly") is now represented *in code* — a host that genuinely needs multi-tenant sets `mode = "multi-tenant"` with `lib.mkForce` and the change is loud in the diff.
- **It does not overlap with canonical.** Cross-framework quantitative values stay in canonical; qualitative shape values stay here.

## Override ergonomics

Same as canonical: defaults are at `mkOptionDefault` priority, so a host overrides via `lib.mkForce`. Typical overrides:

```nix
# Single-tenant host in a high-physical-security facility.
system.compliance.threatModel.outOfScope = lib.mkForce (config.system.compliance.threatModel.outOfScope ++ [ "hypervisor-escape" ]);

# Multi-tenant migration — will require module changes before this works.
system.compliance.tenancy.mode = lib.mkForce "multi-tenant";
```

## Interaction with future modules

The expected consumer map:

| Module (future) | Reads | Uses for |
|---|---|---|
| `agent-sandbox` | `dataClassification.tiers`, `tenancy.mode` | Gate handling of Restricted data; allocate per-tenant UIDs if multi-tenant |
| `ai-services` | `dataClassification.tiers`, `threatModel.adversaries` | Enable/disable prompt-injection mitigations based on adversary list |
| `audit-and-aide` | `dataClassification.tiers` | Emit classification-aware audit records |
| `audit-and-aide` evidence generator (ARCH-10) | all of the above | Serialise meta state into weekly evidence snapshot |

None of these modules exist yet as real code. Meta ships the option shape so they can consume it on day one when they do.

## Gotchas encountered

- **`types.submodule` defaults must set every leaf.** Partial defaults fail at eval with "option accessed but has no value." The three top-level options each set every nested leaf.
- **Single-value enums are a pattern now.** Three examples in the repo: `canonical.firewall.backend`, `canonical.firewall.defaultInbound`, and the new `dataClassification.scheme`. All three declare intent that the single value IS the project's committed choice; the enum makes a deviant future assignment fail loudly.
- **Free-form `types.str` vs typed enum is a real design choice.** Chose enum for `adversaries` + `outOfScope` (finite sets, adding a case is rare) and str for `crownJewels` (proliferates with business context, an enum would force categorisation premature to the work).

## Suggested wiki compile targets

- `wiki/architecture/meta-module.md` (new) — the three options, the qualitative-vs-quantitative split vs canonical, the consumer map.
- Extend `wiki/architecture/threat-model.md` (existing) — cross-link into `modules/meta/default.nix` so the prose narrative points at the code declaration of the same concepts.
- `wiki/review-findings/lessons-learned.md` — consider a light entry on "single-value enums declare intent" as a Nix-module idiom worth knowing.
