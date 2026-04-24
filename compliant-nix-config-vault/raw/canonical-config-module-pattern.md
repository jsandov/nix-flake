# Canonical configuration module — design notes

Session notes from implementing ARCH-02 (extract Appendix A into `modules/canonical/default.nix`). Captures design decisions and alternatives so the next compile pass can distill into wiki articles.

## Goal

Make Appendix A's resolved values mechanically enforced rather than prose-only. Every framework module (stig-baseline, gpu-node, lan-only-network, audit-and-aide, agent-sandbox, ai-services) consumes values from `config.canonical.*` rather than redeclaring them inline. If a PRD module and the canonical module disagree, the canonical module wins — MASTER-REVIEW Systemic Issue #1 resolved structurally.

## Shape — NixOS module, not plain attrset

Two shapes were evaluated:

| Shape | Mechanism | Verdict |
|---|---|---|
| A — NixOS module declaring `options.canonical.*` | Downstream modules read `config.canonical.*`; overrides go through `lib.mkForce`; values show up in `nixos-option` introspection. | **Chosen.** |
| B — Plain attrset in a `.nix` file, imported via `let canonical = import ./canonical; in ...` | Simpler but bypasses the module system — no type checking, no priority-aware overrides, no way for a host to re-bind a single value without forking. | Rejected. |

Shape A integrates with the module system properly. Every downstream module that imports the flake gets `config.canonical.*` for free — no explicit import line needed inside each stig/lan/ai module.

## Types

Three kinds of structured values appear in Appendix A, and each gets a different type:

- **Grouped settings with distinct semantics** (SSH settings, systemd hardening directives, encryption policy) — `types.submodule { options = { ... }; }`. Each field fully typed. Loud errors when a downstream module reads a typo'd field.
- **Flat key-value tables** (patching SLAs, scanning cadences) — `types.attrsOf types.str`. The cadence/timeline strings are symbolic ("30day", "weekly"); consumers translate to concrete NixOS options.
- **Ordered records** (tmpfiles rules, AIDE paths) — `types.listOf (types.submodule { ... })`. Order matters for tmpfiles layering; a list of submodules preserves it.

## Values that look like strings but should be consumed symbolically

Several Appendix A values are strings that a NixOS option expects as a different type:

- `journalMaxRetention = "365day"` — `services.journald.extraConfig` takes this as-is; but `systemd.timers.*.timerConfig.OnCalendar` takes the same cadence differently. The canonical module keeps the symbolic form; each consumer translates.
- `sshListen = "lan"` — this is a symbolic target. The `stig-baseline` or host module resolves "lan" to the real LAN interface address (e.g., `192.168.1.50`) at deployment time. The canonical module must NOT hardcode the deployment-specific IP.
- `clientAliveInterval = 600` — typed as `types.ints.positive` because `services.openssh.settings.ClientAliveInterval` accepts an int directly; consumers use the value verbatim.
- `tlsCiphers = "ECDHE-...:..."` — single colon-separated string because Nginx consumes it that way. Downstream modules must not split and re-join.

The rule: canonical preserves Appendix A's concrete value when it's directly consumable by the downstream NixOS option. It preserves the symbolic form when the same value feeds multiple different consumers that each need to translate.

## Two-list pattern for CUDA carve-outs

A.3's `MemoryDenyWriteExecute` split (required on non-CUDA services, forbidden on CUDA services) is expressed as two explicit lists:

```nix
memoryDenyWriteExecuteServices = [ "agent-runner" "ai-api" ];
memoryDenyWriteExecuteExempt = [ "ollama" ];
```

Downstream modules check membership and emit the directive accordingly. This is more ergonomic than a per-service attrset and makes the intent auditable — grep for the exempt list and you know which services depend on W+X memory.

## Override ergonomics

A host that genuinely needs a different canonical value (e.g., a smaller `lockoutThreshold` on a dev box) can do:

```nix
canonical.auth.lockoutThreshold = lib.mkForce 10;
```

`lib.mkForce` is required intentionally: the canonical module uses `mkOption { default = ...; }` which sets the default at `lib.mkOptionDefault` priority. Any plain assignment at a host still resolves against the default; a deliberate override must be loud.

## What the canonical module does NOT do

- **It does not USE the values.** Setting `services.openssh.settings.KexAlgorithms = config.canonical.ssh.kexAlgorithms` is the job of the `stig-baseline` module (or whichever module owns SSH). The canonical module is an option declaration, not a consumer.
- **It does not resolve host-specific deployment values.** Symbols like `sshListen = "lan"` stay symbolic. The host-level module resolves them at deployment.
- **It does not overlap with `modules/meta/default.nix` (ARCH-08).** Canonical holds Appendix A settings. Meta will hold threat model, data classification, tenancy — qualitative system metadata. The two modules coexist.

## Interaction with ARCH-04 (Resolved Settings Table)

ARCH-04 produces `docs/resolved-settings.yaml` — a machine-readable version of Appendix A with `{setting, value, driving_framework, rejected_values, rationale_link}` per row. The canonical module is the **Nix-consumable** view; the resolved-settings YAML is the **audit-consumable** view. They should be generated from the same source eventually; for the skeleton PR they are hand-maintained in parallel and a CI check (ARCH-17 acceptance-criteria harness) will later enforce agreement.

## Gotchas encountered

- **`types.enum [ "nftables" ]` with one entry** — chosen deliberately even though a single-value enum looks redundant. It declares intent: nftables is the *only* legal value. A future PR that tries to set `canonical.firewall.backend = "iptables"` fails at evaluation with a clear error instead of silently landing.
- **Nested `types.submodule` with defaults on every field** — verbose, but `mkOption` requires either a default or a downstream `config` assignment. Partial defaults on a submodule cause `The option ... was accessed but has no value` at eval time. Set defaults on every leaf.
- **`types.attrsOf types.str` for simple tables** — looser than a fully-typed submodule, but Appendix A tables that are just "category → cadence" don't benefit from a named type per entry. Submodules become valuable when consumers need type-safe field access.

## Suggested wiki compile targets

- `wiki/shared-controls/canonical-config-module.md` — the module pattern, override mechanics, the three type patterns, consumer contract.
- `wiki/architecture/module-composition-contract.md` — once a handful of modules consume canonical, document the "declare once, read everywhere" contract and how boundary lints (ARCH-16) enforce it.
