# PRD Snippet Tiers

A NixOS flake project with a rich PRD suite has three distinct categories of Nix code, each with different expectations about correctness, update discipline, and how a reader should treat them. Mixing the tiers produces the "why does this snippet say X but the implementation does Y?" confusion that drove [[../review-findings/master-review|MASTER-REVIEW Systemic Issue #1]].

## The Three Tiers

| Tier | Lives in | Correctness contract | Update trigger |
|---|---|---|---|
| **Load-bearing** | `docs/prd/prd.md` Appendix A, `docs/resolved-settings.yaml`, `modules/canonical/default.nix`, `modules/*/default.nix` | Every value is the resolved canonical value. CI must pass. | Canonical-value change (needs PR across all three artifacts). |
| **Illustrative** | Framework-specific PRDs (`docs/prd/prd-nist-*.md`, `prd-hipaa.md`, `prd-pci-dss.md`, `prd-stig-disa.md`, `prd-hitrust.md`, `prd-ai-governance.md`, `prd-owasp.md`) | Syntactically valid NixOS 24.11+. No phantom options. May use symbolic placeholders (`<LAN_INTERFACE_IP>`, `"lan"`) that a deployment resolves. | Broken-Nix discovery (fix in place) or canonical-value update (snippet reflects new canonical). |
| **Reference** | Wiki `wiki/**/*.md` code blocks | Concise, focused on one idiom, with working cross-links. | Pattern change (rewrite the article) or compile from a new raw note. |

## How to tell which tier a snippet is in

Read the enclosing file path:

- `modules/**/*.nix` or `hosts/**/*.nix` → load-bearing. Broken Nix here fails CI.
- `docs/prd/prd.md` Appendix A → load-bearing. Must agree with `modules/canonical/default.nix` and `docs/resolved-settings.yaml`.
- `docs/prd/prd-<framework>.md` → illustrative. Readers should treat as "this is the shape of the solution; check Appendix A for the specific resolved value."
- `compliant-nix-config-vault/wiki/**/*.md` → reference. Short, pedagogical, cross-linked.

## Authority Rules

When two tiers appear to disagree:

1. **Load-bearing beats everything else.** If `modules/canonical/default.nix` says `clientAliveInterval = 600` and a framework PRD snippet shows `300`, the PRD snippet is wrong. File a fix.
2. **Illustrative beats reference** — because illustrative snippets must evaluate (caught by CI for any copy-paste into a real module), whereas reference articles are descriptive.
3. **Never rewrite illustrative snippets to be canonical.** Illustrative snippets can and should use placeholders (`<LAN_INTERFACE_IP>`, `"lan"`, `<deployment-specific-IP>`) so the snippet reads right for the framework in question without hardcoding deployment details.

## What placeholders look like across tiers

| Concept | Load-bearing | Illustrative | Reference |
|---|---|---|---|
| LAN interface address | resolved at host-module load (`config.networking.interfaces.<name>.ipv4.addresses`) | `<LAN_INTERFACE_IP>` | `"192.168.1.50"` or `"<LAN_IP>"` in a short example |
| Canonical cipher list | exact list in `canonical.ssh.ciphers` | same exact list (must match), since this is a canonical value | pointer: "see [[canonical-config]]" |
| Deployment DNS server | parameterised, set by host module | `"10.0.0.1"` as an adjustable example | parameterised language ("the LAN DNS server") |

## Gotchas and Edge Cases

- **Comments about forbidden patterns** are not the pattern itself. `environment.etc."login.defs"` in a "DO NOT use" comment is fine; the same string in an actual config block is broken. Hence the [[ci-gate#when-to-lint-vs-when-to-sweep|lint-vs-sweep rule]].
- **Shebangs** (`#!/usr/bin/env bash`) look like FHS path references but are legitimate — `/usr/bin/env` exists on NixOS via systemd compatibility.
- **Code blocks showing what to replace** — illustrative PRD snippets sometimes show a "before" and an "after" for pedagogical reasons. The before is broken-by-intent and the after is the fix; a lint on the before would be a false-positive. Wrap before-examples in a comment or quoted shell syntax.

## Related

- [[../shared-controls/canonical-config]] — the load-bearing runtime artifact (canonical.nix) and its audit sibling (resolved-settings.yaml).
- [[../review-findings/lessons-learned]] entry 30 — the tier-mismatch failure mode and its fix.

## Key Takeaways

- Three tiers with three different correctness contracts — know which you're writing.
- Load-bearing must agree across `prd.md` Appendix A, `resolved-settings.yaml`, `modules/canonical/*`, and `modules/*`.
- Illustrative snippets must evaluate but may use placeholders — do not inline deployment-specific values.
- Reference snippets are short and focused on a single idiom.
- A canonical-value change requires a synchronised update across all load-bearing artifacts in the same PR.
