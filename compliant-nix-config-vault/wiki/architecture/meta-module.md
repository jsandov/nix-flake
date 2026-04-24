# Meta Module

The project's qualitative metadata declared as NixOS options. Complements [[../shared-controls/canonical-config|canonical]]: canonical holds cross-framework-*resolved* quantitative values (Appendix A); meta holds the qualitative *shape* of the deployment — adversaries, crown-jewel data, classification scheme, tenancy.

## Why Separate from Canonical

Two distinct audit narratives:

| | Canonical | Meta |
|---|---|---|
| Content | Quantitative values (log retention, SSH ciphers, password policy) | Qualitative shape (adversaries, data tiers, tenancy) |
| Origin | Cross-framework *resolution* | Project *declaration* |
| Consumer-driven change | Rare (Appendix A is stable) | Sometimes (re-threat-model, re-classify) |
| Audit question it answers | "How did you reconcile framework conflicts?" | "What did you design for?" |

Mixing them would muddle the audit narrative — a compliance reviewer reading "tenancy = single-tenant" has a different question in mind than one reading "clientAliveInterval = 600."

## The Three Options

All under `options.system.compliance.*` with typed submodules + safe defaults.

### `threatModel`

- `adversaries` — enum list. In-scope adversary types. Default: insider-unprivileged, external-LAN-unauthorised, supply-chain-compromise, malicious-model-upstream, prompt-injection-via-user-input.
- `crownJewels` — free-form `listOf str`. Crown-jewel data classes. Free-form because labels proliferate with business context (ePHI vs PII vs CHD vs "model weights"); an enum would force premature categorisation.
- `outOfScope` — enum list. Explicitly accepted out-of-scope attacks. Documenting prevents scope creep. Default: physical-access, nation-state-actor, rubber-hose-cryptanalysis.

The `adversaries` / `outOfScope` enums vs `crownJewels` str list is a deliberate shape decision: adversary types come from a small finite vocabulary; crown-jewel labels vary with business context.

### `dataClassification`

- `scheme` — single-value enum `four-tier-public-internal-sensitive-restricted`. Intent-declaration pattern (see below).
- `tiers` — ordered `listOf submodule` with `name`, `level`, `examples`, `handling`. Four tiers: Public / Internal / Sensitive / Restricted.

The `handling` field is prose — consumed by [[../shared-controls/canonical-config|evidence generation]] (ARCH-10, future) to emit per-tier handling requirements as audit evidence without duplicating.

### `tenancy`

- `mode` — enum `single-tenant | multi-tenant`. Default `single-tenant`.
- `rationale` — string. Short prose explaining the choice.

Most consequential option in meta — changing to multi-tenant invalidates the sops recipient model, the agent-sandbox UID scheme, the model-registry layout, and the audit-stream architecture. The rationale string becomes evidence for compliance assessors.

## Declare-Not-Enforce

Same pattern as canonical and secrets: this module **declares** options; downstream modules **consume** them. An `agent-sandbox` module gating on `config.system.compliance.dataClassification.tiers` can refuse to handle Restricted data without encryption — that enforcement is the agent-sandbox module's job, not meta's.

## Expected Consumers

| Module (future) | Reads | Uses for |
|---|---|---|
| `agent-sandbox` (AI-08) | `dataClassification.tiers`, `tenancy.mode` | Gate Restricted data; per-tenant UIDs in multi-tenant mode |
| `ai-services` (AI-09) | `dataClassification.tiers`, `threatModel.adversaries` | Enable/disable prompt-injection mitigations per adversary list |
| `audit-and-aide` | `dataClassification.tiers` | Classification-aware audit records |
| Evidence generator (ARCH-10) | all of the above | Weekly evidence snapshot serialising meta state |

None of these modules exist as real code yet. Meta ships the option shape so downstream PRs can consume on day one.

## Override Ergonomics

```nix
# Add an out-of-scope attack
system.compliance.threatModel.outOfScope = lib.mkForce
  (config.system.compliance.threatModel.outOfScope ++ [ "hypervisor-escape" ]);

# Multi-tenant migration (requires module changes before this works)
system.compliance.tenancy.mode = lib.mkForce "multi-tenant";
```

`lib.mkForce` is required because defaults are at `mkOptionDefault` priority (same rule as canonical).

## Single-Value Enum Pattern

`canonical.firewall.backend = types.enum [ "nftables" ]`, `canonical.firewall.defaultInbound = types.enum [ "deny" ]`, and now `dataClassification.scheme = types.enum [ "four-tier-..." ]` all use the single-value enum to declare that **this value IS the project's committed choice**. A future PR that tries to deviate fails at eval with a clear error instead of silently landing.

Recognise the pattern, reuse it: it costs one line of type declaration and protects against silent drift.

## Relation to Residual Risks

[[../shared-controls/residual-risks-register|docs/residual-risks.md]] is meta's narrative companion. Meta says "we accept physical-access is out of scope"; residual-risks row 1 says "here's what that acceptance means concretely for ePHI in RAM."

## Key Takeaways

- Meta holds qualitative shape; canonical holds quantitative values. Separate for audit clarity.
- Three options under `options.system.compliance.*`: `threatModel`, `dataClassification`, `tenancy`.
- Declare-not-enforce: downstream modules read, gate, or enforce based on meta.
- `tenancy.mode` default is `single-tenant`; changing it invalidates multiple other modules' design.
- Single-value enums declare committed project choices; use the pattern when a value is non-negotiable.
- Pairs with [[../shared-controls/residual-risks-register|residual risks]] as narrative complement.
