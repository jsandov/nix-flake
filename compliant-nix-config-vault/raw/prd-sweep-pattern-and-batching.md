# PRD-sweep pattern, batching heuristic, and phase observation

Notes accumulated across ARCH-06, INFRA-03, and INFRA-01+02 that weren't captured in those TODO-specific raw notes. Generalisable patterns worth lifting to wiki before the next slice of work (AI-side Ollama fixes).

## Where we are in the project

9 of 16 P0s done. The completed set is almost entirely **PRD prose cleanup** plus a small amount of NixOS module scaffolding (canonical + secrets). No real module code has landed yet — `modules/stig-baseline/`, `modules/gpu-node/`, `modules/lan-only-network/`, `modules/audit-and-aide/`, `modules/agent-sandbox/`, `modules/ai-services/` are all still stubs.

This means the current phase is best named **PRD-cleanup phase**: fixing broken Nix snippets *in the PRDs* before they can infect a module PR via copy-paste. The next phase will be **module-construction**, which is a different shape of work (real options, real option consumers, real activation behaviour).

Worth saying explicitly because it changes how to budget work and how to think about "is this done?":

- PRD-cleanup TODO: "done" = every PRD snippet is correct + a lint prevents regression where possible. Mostly markdown diffs.
- Module-construction TODO: "done" = a NixOS module that consumes `canonical.*` values, exposes any new options, and has consumer modules reading from it. Mostly Nix diffs.

## Pattern 1 — The PRD-sweep TODO shape

Three recent TODOs had identical shape:

| TODO | Shape |
|---|---|
| ARCH-06 (FHS paths) | Grep for broken pattern → fix 3 snippets → add narrow lint |
| INFRA-03 (phantom options) | Grep for broken pattern → fix 4 snippets → skip lint (false-positive risk) |
| INFRA-01+02 (iptables/bindings) | Grep for broken pattern → fix 3 snippets → no lint (pattern already blocked elsewhere) |

Generalised procedure:

1. Grep the PRD tree for the broken pattern. Include the MASTER-REVIEW historical refs in the grep to confirm nothing new has appeared.
2. Categorise hits into: **broken config** (fix), **descriptive prose** (leave), **shebangs / examples** (leave), **MASTER-REVIEW historical** (leave).
3. Fix every broken-config hit using the canonical replacement value from `docs/resolved-settings.yaml` or `modules/canonical/default.nix`.
4. Decide lint or sweep (see [[../architecture/ci-gate#when-to-lint-vs-when-to-sweep|the lint-vs-sweep rule]]). If lint, add a narrow regex that only matches the broken shape, not descriptive prose.
5. Drop a raw note naming the fix, the path mapping, and anything surprising.

Time cost: 15–30 min per sweep TODO, including CI iteration. The cadence works because ARCH-03 is the backstop — if you miss a case, the broad CI lint catches it once real module code lands.

## Pattern 2 — Batched-PR exception to "one TODO per PR"

Lesson 23 says "one P0 TODO per PR." INFRA-01 and INFRA-02 were landed together because they act on the same Nix snippets in the same three PRDs. Batching was correct there.

**The test:** would splitting the work force a reviewer to page in the same context twice? If yes, batch. If no, split.

Concrete examples from the current queue:

- **INFRA-01 + INFRA-02** (firewall backend + listener bindings) — same snippets, same reviewer mental model → batch. Done.
- **AI-01 + AI-02** (MemoryDenyWriteExecute carve-out + WatchdogSec removal) — both act on the Ollama systemd unit block in the same PRDs → candidate for batch.
- **AI-06 + AI-07** (OLLAMA_HOST loopback + OLLAMA_NOPRUNE reframing) — both are Ollama environment settings → candidate for batch.
- **AI-03 + AI-05** (model-fetch script + core-dump disable) — unrelated territory → split.

Rule of thumb: batch when the commits would touch overlapping files and the reviewer's context is the same. Split when they touch different modules or different concerns.

## Pattern 3 — Pre-check TODO status with grep before claiming

AI-06 ("Lock OLLAMA_HOST to loopback") was preemptively satisfied by earlier ARCH-05 and INFRA-01+02 sweeps. Every `OLLAMA_HOST` reference in the PRD tree is already `127.0.0.1:11434`. The TODO text describes a past-tense bug that no longer exists in current snippets.

**Rule:** before claiming a PRD-sweep TODO, grep for the target pattern. If the search returns only historical references (MASTER-REVIEW, explanatory prose), the TODO is already done — close the bead with a note about when it was silently fixed.

Less obvious form: before a module-construction TODO, check whether `modules/canonical/default.nix` already exposes the option the module needs. If yes, the module just reads from `config.canonical.*`; if no, the module PR has to extend canonical first.

The pre-check is usually 30 seconds. It saves opening a PR that produces a diff of zero lines.

## Pattern 4 — "Is this snippet illustrative or load-bearing?"

A repeating judgment call on PRD edits: should the snippet be a runnable NixOS config, or is it OK for it to be illustrative?

The project convention that's been forming:

- **Appendix A tables in `prd.md`** — load-bearing. Every value is the resolved canonical value and must match `modules/canonical/default.nix` exactly. Changes here require a canonical update in the same PR.
- **Framework-specific PRD snippets** (NIST/HIPAA/STIG/HITRUST) — illustrative. They show the shape of the solution, but the implementation authority is `modules/canonical/*` and `docs/resolved-settings.yaml`. Snippets should still *evaluate* (no phantom options, no broken syntax), but they can use placeholders like `<LAN_INTERFACE_IP>` or symbolic strings like `"lan"` that a real deployment resolves.
- **Code blocks in `compliant-nix-config-vault/wiki/`** — reference-quality. Shorter than PRD snippets, focused on one idiom, with working cross-links.

The project is not fully consistent on this yet. Worth a short wiki entry formalising the three tiers.

## Pattern 5 — The "one PR per reviewer context" cost

A side-effect of the granular-PR + batched-compile cadence: review attention is the dominant cost once CI + iteration loops are tight (<3 min per CI run, 1–2 min per merge). Writing 4 raw notes during a session isn't expensive; writing 4 mega-PRs with overlapping context is.

Concrete numbers from this session:

- 15 merged PRs across ~3 hours.
- 9 feature PRs at ~10 min each (edit + commit + push + PR + CI watch + merge).
- 5 compile PRs at ~5 min each.
- 1 hotfix at 10 min.

If the same work had been 3 mega-PRs, each would have taken 30+ min to review properly, with higher risk of merging something broken (the #26 incident would have been worse).

Rule: at this project's CI speed, more granular PRs are strictly better than fewer big ones. The cost of opening a PR is smaller than the cost of context-switching in review.

## Pattern 6 — Raw-note structure that compiles well

Across 7 raw notes written this session, a stable structure has emerged. Notes that compiled cleanly into wiki articles shared these elements:

1. One-paragraph "what this is" at the top — goal, not history.
2. Specific decisions made, with alternatives considered and rejected.
3. Gotchas encountered *during implementation*, not just general advice.
4. A "suggested wiki compile targets" section at the end pointing at concrete file paths.

Notes that didn't compile well (or only partially) lacked the "suggested compile targets" hint — the compile pass then had to guess at scope. Worth adopting as a convention: **every raw note ends with explicit compile targets.**

## Next slice of work — AI-side Ollama fixes

Reading ahead so the next session starts fast:

- **AI-06** — likely already resolved; confirm with grep, close the bead with a note.
- **AI-01 + AI-02** — batchable; both act on the Ollama systemd unit block. Target: exempt `ollama.service` from `MemoryDenyWriteExecute`; remove `WatchdogSec=300`; add an external systemd timer health check.
- **AI-07** — one-line prose clarification that `OLLAMA_NOPRUNE=1` is a storage flag, not a security control. May batch with AI-06 confirmation.
- **AI-03** — script rewrite for `ai-model-fetch`. Ollama stores models as content-addressed blobs in `/var/lib/ollama/models/blobs/sha256-<hex>`, not `.bin` files. Script must target the blob + manifest layout.
- **AI-05** — core-dump disable. `systemd.coredump.extraConfig = "Storage=none"` + `boot.kernel.sysctl."kernel.core_pattern" = "|/bin/false"`. Both values already canonical; just confirm/adjust PRD snippets.

Estimated: 3 PRs (AI-01+02, AI-06+AI-07, AI-03, AI-05) + one compile pass. Maybe 45–60 min to finish the P0 queue except the human-blocked AI-04.

## Suggested wiki compile targets

- `wiki/review-findings/lessons-learned.md` — add lessons 28–31:
  - 28: "PRD-sweep TODO shape" (grep → categorise → fix → lint-or-skip)
  - 29: "Pre-check TODO status before claiming" (grep first)
  - 30: "Load-bearing vs illustrative vs reference snippets" — the three-tier convention
  - 31: "Granular PRs beat mega-PRs once CI is fast" (the review-attention cost)
- `wiki/architecture/prd-snippet-tiers.md` (new) — the three-tier convention from Pattern 4 with examples.
- Consider extending `wiki/architecture/ci-gate.md` "when to lint vs sweep" section with Pattern 1's sweep procedure.
- Raw-note convention (Pattern 6) — not wiki-worthy on its own; fold into a sentence in `lessons-learned.md` if anywhere.
