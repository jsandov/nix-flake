# ARCH-07 — Secrets-in-Nix-store leakage lint

Session notes from adding the third CI lint layer. Complements the broad FHS-path lint (ARCH-03) and the narrow docs FHS-path lint (ARCH-06). Goal: catch a secret landing in `/nix/store` *at PR review time*, before it can be garbage-collected or scraped.

## Why this TODO matters

`/nix/store` has 0444/0555 permissions. Once a secret-bearing derivation is realised, the file is readable by every user and process, and the underlying blocks are not securely wiped on garbage collection. [[../nixos-platform/nixos-gotchas|Gotcha #1]] frames this as the single largest operational risk on NixOS. [[../shared-controls/secrets-management]] commits the project to sops-nix as the only legal way to introduce secrets — this lint enforces that commitment in code review.

## The three heuristic patterns

A fully eval-based scan would walk every derivation output and inspect its contents for secret-shaped data. That's ARCH-17's territory (the acceptance-criteria test harness). For a skeleton CI, three targeted regexes over `modules/` + `hosts/` catch the common cases with near-zero false-positive rate:

### Pattern A — PEM inside a Nix builder

```
(pkgs\.writeText|builtins\.toFile)[^)]*-----BEGIN
```

Catches the shape `pkgs.writeText "name" "-----BEGIN PRIVATE KEY-----..."`. Any PEM marker on the same line as a writeText/toFile call is treated as a leak. Multi-line heredoc content would need a more elaborate parser; accepting the lint's single-line limitation because PEM-in-heredoc is rare in practice and would get caught in PR review.

### Pattern B — Long hex runs inside a Nix builder

```
(pkgs\.writeText|builtins\.toFile)[^)]*[A-Fa-f0-9]{40}
```

Catches sha1-shaped (40 chars) or longer hex strings inside a writeText/toFile call. These are the standard shape of API tokens, bearer tokens, and signing keys.

**False-positive analysis:** legitimate hashes (nixpkgs SHA pins, input narHashes, fetchFromGitHub sha256 attrs) live outside writeText bodies — in `flake.lock`, in input declarations, or in `fetchurl { sha256 = "..."; }` calls. None of those match the "inside a writeText/toFile" context. Running the pattern against the current repo produces zero hits; will revisit if real-world use cases surface false positives.

### Pattern C — Literal-value secret-named env var

```
(TOKEN|SECRET|PASSWORD|PRIVATE_KEY|API_KEY|AUTH_KEY)[A-Z_]*[[:space:]]*=[[:space:]]*"[^$"][^"]*"
```

Catches `API_TOKEN = "abc123"` where the value is a non-empty string that does NOT start with `$` (which would indicate interpolation, typically pulling from `config.sops.secrets.*.path`).

**Allowed forms** (pattern does NOT fire on):

- `API_TOKEN = "${config.sops.secrets.api-token.path}";` — starts with `$`
- `API_TOKEN = "";` — `[^"]*` requires at least one non-quote char
- `API_TOKEN = null;` — no quotes
- `API_TOKEN = config.sops.secrets.api-token.path;` — no quotes around a bare reference

**Blocked forms:**

- `API_TOKEN = "literal-secret-value";`
- `SSH_PRIVATE_KEY = "-----BEGIN OPENSSH PRIVATE KEY-----...";` — caught by Pattern A first
- `DB_PASSWORD = "hunter2";`

## Scope decision: modules/ + hosts/ only

Per [[../architecture/prd-snippet-tiers|the three-tier convention]], PRD snippets are illustrative and may legitimately contain example secret-shaped content for pedagogy (e.g., showing what an `API_KEY = "sk-abc..."` entry looks like as a negative example in a HIPAA §164.312(a)(1) violation discussion). Running this lint against PRDs would produce false positives.

The three-tier convention says: load-bearing code (`modules/`, `hosts/`) must not contain literal secrets. Illustrative PRD snippets can. Reference wiki snippets can include `<placeholder>`-style non-secrets but not real secret-shaped values. Scope to load-bearing, full stop.

## What this lint does NOT cover (deliberately)

- **`ExecStart` lines interpolating non-`/run/secrets` paths for secrets.** Would require context-aware heuristics (is this path a secret?) that grep can't express. Review-only.
- **Secrets in environment variables passed via `systemd.services.<name>.environment`.** If the variable name doesn't match the pattern (say `MY_HASH` or `OPAQUE_BLOB`), it slips through. Acceptable gap because the sops-nix workflow is well-documented and the pattern covers the standard names.
- **Eval-time introspection of realised derivation contents.** That's ARCH-17's charter when the test harness ships.

The lint is explicitly a **heuristic first line of defence**, not a proof. PR review is the backstop.

## Rollout test

Ran each pattern against the current repo before enabling. All three returned zero hits. Safe to enable without breaking existing PRs.

A future deliberate-false-positive test would validate that the lint catches new leaks — add a scratch branch with `API_TOKEN = "deadbeef"` and confirm CI fails. Not doing that in this PR; the grep logic is simple enough to audit visually.

## Suggested wiki compile targets

- `wiki/architecture/ci-gate.md` — extend the "What the Gate Runs" numbered list from 5 to 6 items, and the stack-check table from 4 to 5. Short update.
- `wiki/shared-controls/secrets-management.md` — cross-reference the lint under a new "Mechanical enforcement" section near the top.
- `wiki/review-findings/lessons-learned.md` — optional entry 32 if we generalise "heuristic lint now, eval-based test harness later" as a pattern. Small; may not need its own entry.
