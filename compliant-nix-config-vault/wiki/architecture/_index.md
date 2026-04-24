# Architecture

System architecture for the compliance-mapped NixOS AI server.

## Articles

- [[flake-modules]] — The six flake modules and their responsibilities
- [[flake-skeleton-pattern]] — Minimum-viable scaffold so a flake evaluates without real hardware
- [[ci-gate]] — The CI contract that catches broken Nix before it merges
- [[prd-snippet-tiers]] — Three-tier convention for Nix snippets across PRDs, modules, and wiki
- [[meta-module]] — Threat model, data classification, tenancy as typed NixOS options
- [[boot-integrity]] — Secure Boot via lanzaboote; dormant/active mode gating; priority dance
- [[nix-implementation-patterns]] — Reusable patterns for module composition and option design
- [[data-flows]] — How data moves through the inference and agent pipelines
- [[threat-model]] — Protected assets, adversary model, and scope boundaries
- [[build-and-test-strategy]] — nixos-generators + runNixOSTest + nixos-anywhere + disko; CI cadence tiers (per-PR fast / nightly full / release-only signing)
- [[module-aggregator-pattern]] — when to split a module family into `imports = [ ./a.nix ./b.nix ]`; aggregator-owned cross-submodule defaults; ARCH-16 compatibility
