# Resolved Settings YAML — format + contract

Session notes from implementing ARCH-04 (`docs/resolved-settings.yaml`). Captures the schema choices, the contract with `modules/canonical/default.nix`, and the audit narrative the file is meant to support.

## What this YAML is for

Two distinct audiences, one source of truth:

1. **Auditors / compliance reviewers** need a flat, parseable record of every cross-framework setting the implementation *resolved* — what the final value is, which framework drove it, which alternatives were proposed and why they were rejected.
2. **Implementers and future PRs** need the rejection reasons to survive so a proposal to reopen a setting (e.g., "can we use 12-character passwords?") can be matched against the original rejection before any code lands.

A YAML file covers both — human-skimmable, tool-parseable, diff-reviewable in PRs.

## Relationship to `modules/canonical/default.nix`

The canonical module is the **Nix-consumable** view. The YAML is the **audit-consumable** view. They MUST agree on every value; they disagree on metadata:

| Field | canonical.nix | resolved-settings.yaml |
|---|---|---|
| Value | ✓ as `mkOption { default = ...; }` | ✓ as `value:` |
| Type | ✓ via `types.*` | implicit (YAML scalar/list) |
| Driving framework | ✗ (prose only in comments) | ✓ as `driving_frameworks:` |
| Rejected values + reasons | ✗ | ✓ as `rejected_values:` |
| Rationale link back to PRD | ✗ (shared intro comment) | ✓ per-row as `rationale_link:` |

Canonical is the runtime source — CI evaluates it on every PR. The YAML is the review source — updated whenever the canonical value changes.

**ARCH-17** (acceptance-criteria test harness) will later parse the YAML, walk `config.canonical.*`, and fail the build if any row's `value` does not match the canonical default. Until ARCH-17 ships, agreement is maintained by human discipline + PR review.

## Schema

```yaml
schema_version: 1
source: docs/prd/prd.md Appendix A
last_updated: 2026-04-24
canonical_nix: modules/canonical/default.nix

rows:
  - id: A.N.slug             # Stable identifier — never renumber.
    section: A.N Section     # Matches Appendix A subsection heading.
    setting: Human name      # One-line description of what this setting is.
    canonical_path: canonical.foo.bar   # Dotted path into canonical.nix.
    value: <literal>         # YAML scalar/list/map matching the Nix default.
    driving_frameworks: [STIG, NIST]   # One-or-more frameworks that drove the choice.
    consensus: true|false    # True = every framework agreed; omit rejected_values.
    rejected_values:         # Only for consensus: false.
      - value: <literal>
        proposed_by: <framework module or section>
        rejection_reason: >
          Paragraph explaining why this value was not chosen.
    notes: >                 # Optional prose for follow-up context.
      Any clarifications.
    rationale_link: docs/prd/...    # Link back to Appendix A.
```

### Field notes

- **`id`** — stable. Once assigned, never renumber. If a row is superseded, mark it so and add a new row; don't edit the old id.
- **`canonical_path`** — the dotted path an implementer would use in a NixOS module to read the value. Not every row maps to a single option path (e.g., A.11 rows correspond to *entries* in a `canonical.tmpfilesRules` list). In those cases, document the subscript in parentheses.
- **`consensus`** — a compact way to say "no one proposed anything else." Consensus rows get no `rejected_values`. Conflict rows always get at least one.
- **`value`** — use native YAML types (string, int, bool, list, map). Do NOT wrap values in string-escaping unless the canonical Nix type is `str`.
- **`rejection_reason`** — long-form prose. This is the most-valuable field for future PR review. Keep it specific: why *this particular* proposal was rejected, not a general argument.

## What the table does NOT include

- **Pure operational values** (e.g., `journalMaxUse = "10G"`) that are deployment-specific and were never in cross-framework conflict. They live in canonical.nix but don't need provenance rows.
- **Values governed by a single framework with no alternative proposal** — if only HIPAA spoke to it, there's no conflict to record. Include only if the auditor narrative benefits.
- **Code snippets or configuration fragments.** YAML holds values; canonical.nix holds snippets. If an auditor needs the snippet, they follow `canonical_path`.

## Scope decisions for this PR

- 29 rows covering A.1 through A.15, with a row for every conflict resolution and for consensus items where the audit narrative benefits from provenance.
- Left out: the A.8 scanning-cadence table (pure cadences, no conflict), most A.14 options that were pure consensus.
- `rationale_link` uses relative paths to `docs/prd/prd.md` — these should resolve in GitHub PR review and in local Obsidian.

## Gotchas encountered

- **YAML block scalars (`>`)** fold whitespace differently from most humans' intuition. When the rejection reason is multi-line prose, `>` (folded block) gives paragraph-like rendering after a `\n\n`. Single `\n` becomes a space. Tested in a YAML parser before committing.
- **Lists of maps** (`value: ["foo", "bar"]` vs `value: [{path: foo, mode: "0700"}]`) — keep the value shape identical to the canonical default. If the canonical is `types.listOf types.str`, the YAML value is a flat list of strings. Anything else is a desync the test harness will flag.
- **A.11 tmpfiles and A.12 AIDE paths** — each canonical entry is a *record*, so the YAML row references the canonical list by filter expression (e.g., `canonical.tmpfilesRules (path=/var/log/audit)`). ARCH-17 will need to implement that filter to cross-check these rows. Noted, not solved.
- **String coercion of TLS cipher list** — canonical stores as a single colon-separated string, YAML stores as the same string. Easy. If a future decision splits it into a list, update both in the same PR.

## Suggested wiki compile targets

- `wiki/shared-controls/resolved-settings-contract.md` — the audit-vs-runtime contract between `docs/resolved-settings.yaml` and `modules/canonical/default.nix`, the ARCH-17 enforcement plan, how to add a new row.
- `wiki/compliance-frameworks/conflict-resolution-log.md` — a lighter document referencing this YAML as the evidence artefact for every cross-framework resolution decision. Useful for a compliance auditor who wants "show me the resolution history" without reading Appendix A.
