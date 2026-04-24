# Wiki audit — 2026-04-24

## TL;DR

- Findings: broken 4, stale 13, gap 7, style 5.
- Top 3 fixes for follow-up PR:
  1. Purge the `users.allowNoPasswordLogin` skeleton-escape guidance from `nixos-gotchas.md` #17 and `boot-integrity.md` "Related Gotchas" — retired in ARCH-11, still printed as live advice (broken).
  2. Rewrite `architecture/flake-modules.md` + `shared-controls/shared-controls-overview.md` + `compliance-frameworks/cross-framework-matrix.md` to reflect the 9-module reality (canonical, meta, secrets, stig-baseline, audit-and-aide{auditd,evidence}, accounts + stubs gpu-node, lan-only-network, agent-sandbox, ai-services). Every one still talks about 6 modules (stale, gap).
  3. Fix the cross-topic wiki-link prefix problem: 15+ links like `[[hipaa/ephi-data-flow]]` and `[[shared-controls/evidence-generation]]` are written without `../` from non-root locations. Most Obsidian-style renderers resolve these, but a strict compile or a static-site renderer will 404 (style/broken hybrid).

## Audit method

- Read `wiki/_master-index.md`, every `wiki/*/_index.md`, and every article under `architecture/`, `shared-controls/`, `nixos-platform/`, `compliance-frameworks/`, plus `_graph.md`.
- Cross-referenced `modules/canonical/default.nix`, `modules/accounts/default.nix`, `modules/audit-and-aide/{default,auditd,evidence}.nix`, `modules/stig-baseline/default.nix`, `modules/secrets/default.nix`, `docs/resolved-settings.yaml`, `docs/residual-risks.md`.
- Grepped the full wiki tree for `allowNoPasswordLogin`, `ARCH-10`, `ARCH-11`, `agenix`, `QUICK_START`, `six-module`, `14 domains`, and suspicious `[[topic/`-prefixed wiki links.
- Confirmed raw-note inventory under `raw/` (36 files) and which notes post-date PR #48.

## 1. Consistency with shipped code

### Finding 1 — `allowNoPasswordLogin` escape hatch still shown as live advice

- Location: `compliant-nix-config-vault/wiki/nixos-platform/nixos-gotchas.md:122-145` (the "Fix (skeleton)" code block) and `:174` (Key Takeaway bullet).
- Severity: broken.
- Why: ARCH-11 retired the `users.allowNoPasswordLogin = lib.mkDefault true` escape hatch; the admin user in `modules/accounts/default.nix:177-187` now satisfies the NixOS lock-out assertion structurally. The gotcha reads as current-best-practice advice.
- Suggested fix: rewrite #17 as historical context ("was required pre-ARCH-11; see accounts module for current approach"); remove the mkDefault/mkForce snippet or mark it "historical — do not copy."
- Mechanical / judgement: mechanical (narrative rewrite; no value changes).

### Finding 2 — `boot-integrity.md` "Related Gotchas" cross-links escape-hatch advice

- Location: `wiki/architecture/boot-integrity.md:106`.
- Severity: broken.
- Why: same retirement as Finding 1. A reader following the cross-link lands on stale advice without the boot article signalling it.
- Suggested fix: reword the bullet to "`users.mutableUsers = false` is satisfied by the accounts module declaring the admin user with SSH keys. See [[../shared-controls/shared-controls-overview|control 15]] and [[../nixos-platform/nixos-gotchas|#17]] for the pre-ARCH-11 escape-hatch history."
- Mechanical / judgement: mechanical.

### Finding 3 — `auditd-module-pattern.md` still says rules live in `modules/audit-and-aide/default.nix`

- Location: `wiki/nixos-platform/auditd-module-pattern.md:64`.
- Severity: stale.
- Why: ARCH-10 split the module; auditd rules now live in `modules/audit-and-aide/auditd.nix`, and `default.nix` is the aggregator (`modules/audit-and-aide/default.nix:17-23`).
- Suggested fix: replace `modules/audit-and-aide/default.nix` with `modules/audit-and-aide/auditd.nix` in the sentence, and add one line: "Aggregator `default.nix` imports `./auditd.nix` + `./evidence.nix`; see [[../shared-controls/evidence-generation|evidence-generation]]."
- Mechanical / judgement: mechanical.

### Finding 4 — `flake-modules.md` describes six pre-ARCH modules, omits canonical/meta/secrets/accounts

- Location: `wiki/architecture/flake-modules.md:3-64`.
- Severity: stale.
- Why: Real module tree is `canonical/`, `meta/`, `secrets/`, `stig-baseline/`, `audit-and-aide/`, `accounts/` + stubs `gpu-node/`, `lan-only-network/`, `agent-sandbox/`, `ai-services/`. The wiki article predates every ARCH PR and still frames the system as the original six flake modules.
- Suggested fix: add a "Foundation modules" subsection (`canonical`, `meta`, `secrets`, `accounts`) above the existing six; update the dependency diagram; mark `gpu-node`, `agent-sandbox`, `ai-services`, `lan-only-network` as **stubs** explicitly.
- Mechanical / judgement: needs judgement (section authorship + diagram redraw).

### Finding 5 — `shared-controls-overview.md` assigns control 15 (Account Lifecycle) to stig-baseline

- Location: `wiki/shared-controls/shared-controls-overview.md:23`.
- Severity: broken.
- Why: Account Lifecycle is owned by the `accounts` module (ARCH-11). stig-baseline no longer sets account policy beyond `usersMutableUsers` via canonical.
- Suggested fix: change module owner cell to `accounts`.
- Mechanical / judgement: mechanical.

### Finding 6 — `shared-controls-overview.md` assigns control 13 (Secrets Management) to stig-baseline

- Location: `wiki/shared-controls/shared-controls-overview.md:21`.
- Severity: broken.
- Why: Secrets lifecycle is the `secrets/` module (sops-nix); `wiki/shared-controls/secrets-management.md` already points there.
- Suggested fix: change module owner cell to `secrets`.
- Mechanical / judgement: mechanical.

### Finding 7 — `meta-module.md` labels `audit-and-aide` as a future consumer

- Location: `wiki/architecture/meta-module.md:54` and `:35` (ARCH-10 "future").
- Severity: stale.
- Why: `modules/audit-and-aide/` has real code (ARCH-10 evidence framework shipped); ARCH-10 is not future.
- Suggested fix: in the "Expected Consumers" table keep the row but drop "None of these modules exist as real code yet" (`:57`) — ai-services / agent-sandbox are stubs, but audit-and-aide does. Change "ARCH-10, future" to "ARCH-10".
- Mechanical / judgement: mechanical.

### Finding 8 — `boot-integrity.md` describes evidence review as "future ARCH-10"

- Location: `wiki/architecture/boot-integrity.md:99`.
- Severity: stale.
- Why: ARCH-10 landed.
- Suggested fix: drop "future" — the collector now exists and is the right place to point at for sulogin confirmation.
- Mechanical / judgement: mechanical.

### Finding 9 — `cross-framework-matrix.md` only enumerates six pre-ARCH modules

- Location: `wiki/compliance-frameworks/cross-framework-matrix.md:7-14`.
- Severity: stale.
- Why: Same root cause as Finding 4. Matrix has no rows for canonical/meta/secrets/accounts and still names `gpu-node`, `agent-sandbox`, `ai-services` as if they contained real control coverage.
- Suggested fix: rebuild the matrix around the new module set; add a `stub` column so the stub rows are not read as shipped controls.
- Mechanical / judgement: needs judgement (policy: do we want stubs listed at all?).

## 2. Cross-framework value consistency

### Finding 10 — `canonical-config-values.md` omits `passwordMaxAgeDays = 60`

- Location: `wiki/compliance-frameworks/canonical-config-values.md:~47`.
- Severity: gap.
- Why: `modules/canonical/default.nix:212` and `docs/resolved-settings.yaml:~324` both resolve password max age to 60 days (STIG). The wiki's auth table has min length / history / lockout threshold / duration / TMOUT but no max-age row.
- Suggested fix: add row `| Password max age | 60 days | STIG (NIST tension noted) |`.
- Mechanical / judgement: mechanical.

### Finding 11 — `canonical-config-values.md` omits `lockoutFindIntervalSeconds` and `sessionIdleTimeoutSshSeconds`

- Location: `wiki/compliance-frameworks/canonical-config-values.md:~47`.
- Severity: gap.
- Why: `modules/canonical/default.nix:201,202,215,216` declare and default these values but the wiki auth table does not list them; the accounts module embeds both into the access-review evidence (`modules/accounts/default.nix:24-35`).
- Suggested fix: add two rows — `lockoutFindIntervalSeconds = 900`, `sessionIdleTimeoutSshSeconds = 600`.
- Mechanical / judgement: mechanical.

### Finding 12 — `canonical-config-values.md` is silent on `mfaScope` / `mfaMechanism`

- Location: `wiki/compliance-frameworks/canonical-config-values.md`.
- Severity: gap.
- Why: `modules/accounts/default.nix:31-33` reads `canonical.auth.mfaScope` and `mfaMechanism`. Cross-framework MFA is a first-class control but the wiki's canonical-values article never names it.
- Suggested fix: add an "MFA" row with `mfaScope = "all-remote-admin"`, `mfaMechanism = "totp-via-google-authenticator-pam"` (verify exact values against `modules/canonical/default.nix`).
- Mechanical / judgement: mechanical (after verifying exact defaults).

### Finding 13 — HITRUST domain count discrepancy between `frameworks-overview.md` and `hitrust-corrections.md`

- Location: `wiki/compliance-frameworks/frameworks-overview.md:11` says "14 control domains (actual: 19 in v11)"; `wiki/compliance-frameworks/hitrust-corrections.md:7-30` says 19.
- Severity: style (factually consistent, just awkward).
- Why: The parenthetical is an apology for leaving the wrong number in the leading cell. A reader scanning the table only sees "14."
- Suggested fix: flip to "19 control domains (corrected from PRD's 14; see [[hitrust-corrections]])".
- Mechanical / judgement: mechanical.

## 3. Wiki-link hygiene

### Finding 14 — Missing `../` prefix on cross-topic links (pervasive)

- Location: at least the following lines, all written as `[[topic/article]]` from inside a sibling topic folder (Obsidian-relaxed syntax; strict renderers break):
  - `wiki/architecture/data-flows.md:57` `[[hipaa/ephi-data-flow]]`
  - `wiki/architecture/data-flows.md:77` `[[shared-controls/evidence-generation]]`
  - `wiki/architecture/flake-skeleton-pattern.md:63` `[[review-findings/master-review]]`
  - `wiki/architecture/flake-modules.md:29` `[[shared-controls/evidence-generation|evidence generation]]`
  - `wiki/architecture/flake-modules.md:40` `[[ai-governance/model-supply-chain|provenance tracking]]`
  - `wiki/architecture/flake-modules.md:67` `[[compliance-frameworks/cross-framework-matrix]]`
  - `wiki/architecture/threat-model.md:58,59`
  - `wiki/architecture/ci-gate.md:7,23`
  - `wiki/architecture/nix-implementation-patterns.md:179`
  - `wiki/compliance-frameworks/canonical-config-values.md:30`
  - `wiki/compliance-frameworks/cross-framework-matrix.md:3,34`
  - `wiki/compliance-frameworks/hitrust-corrections.md:59`
  - `wiki/compliance-frameworks/frameworks-overview.md:10,12,13,14,17,39`
  - `wiki/nixos-platform/nixos-gotchas.md:3,38,54,166`
  - `wiki/nixos-platform/compliance-advantages.md:15`
  - `wiki/nixos-platform/github-actions-nix-stack.md:3`
  - `wiki/shared-controls/shared-controls-overview.md:3,38,40`
- Severity: style (with broken potential on strict renderers).
- Why: Articles elsewhere (e.g. `nix-implementation-patterns.md`, `meta-module.md`) correctly write `[[../topic/article]]`; the inconsistency is purely historical. The dangling links (#15/#16 below) are worse than the missing-prefix cases.
- Suggested fix: one sweeping rewrite — convert every `[[<topic>/` to `[[../<topic>/` when the article is one level down. Can be done with a single sed, but require human glance to catch the `[[review-findings/master-review|master review]]` variants.
- Mechanical / judgement: mostly mechanical; a linter would catch every case.

### Finding 15 — Dangling link `[[shared-controls/incident-response-hooks]]`

- Location: `wiki/nixos-platform/compliance-advantages.md:15`.
- Severity: broken.
- Why: `shared-controls/incident-response-hooks.md` does not exist. Closest article is `shared-controls-overview.md` control #10 "Incident Response Hooks."
- Suggested fix: either retarget to `[[../shared-controls/shared-controls-overview#core-controls|incident response]]` (fast), or create a dedicated article (gap; see Finding 19).
- Mechanical / judgement: mechanical retarget; article creation is judgement.

### Finding 16 — Dangling link `[[shared-controls/vulnerability-management]]`

- Location: `wiki/nixos-platform/nixos-gotchas.md:54`.
- Severity: broken.
- Why: `shared-controls/vulnerability-management.md` does not exist.
- Suggested fix: retarget to `[[../shared-controls/shared-controls-overview|control 12]]`, or create the article (see Finding 20).
- Mechanical / judgement: mechanical retarget; article creation is judgement.

### Finding 17 — `_graph.md` node `residual-risks` file-name drift

- Location: `wiki/_graph.md:30`.
- Severity: style.
- Why: The ai-security subgraph node is labelled `residual-risks` but the article's file is `ai-security-residual-risks.md`. Mermaid doesn't link to files, so it's not broken — but a reader looking for the node in the filesystem misses it.
- Suggested fix: rename the mermaid node to `ai-security-residual-risks` (or at least add a comment tying the node label to the file name). Consider also adding a `shared-controls/residual-risks-register` node — the graph currently only shows the AI residual-risks article.
- Mechanical / judgement: mechanical.

### Finding 18 — `_graph.md` omits most ARCH-era articles

- Location: `wiki/_graph.md` (whole file).
- Severity: gap.
- Why: The graph predates ARCH-08 (meta), ARCH-09 (boot-integrity), ARCH-10 (evidence-generation), ARCH-02 (canonical-config), and the residual-risks-register. The hub article table at `:89` still lists only four hubs; `canonical-config` under `shared-controls/` and `residual-risks-register` should both be hubs based on inbound-link count.
- Suggested fix: add nodes for `canonical-config` (shared-controls), `residual-risks-register`, `boot-integrity`, `meta-module`, `ci-gate`, `auditd-module-pattern`, and re-derive hub status from real inbound-link counts.
- Mechanical / judgement: judgement (node inclusion + edge re-derivation).

## 4. Coverage gaps

### Finding 19 — No dedicated article on incident-response hooks

- Location: missing under `shared-controls/`.
- Severity: gap.
- Why: `shared-controls-overview.md:18` lists "Incident Response Hooks" (control 10) and `compliance-advantages.md:15` tries to link to one that does not exist.
- Suggested fix: create `shared-controls/incident-response-hooks.md` once ARCH-15 (or whichever TODO wires `OnFailure=notify-admin@`) lands. Until then, retarget links as in Finding 15 and add an "Open follow-ups" bullet in `shared-controls-overview.md`.
- Mechanical / judgement: judgement (wait for shipping code vs write placeholder).

### Finding 20 — No dedicated article on vulnerability management

- Location: missing under `shared-controls/`.
- Severity: gap.
- Why: Same as Finding 16; control 12 exists in the overview, patch timelines are canonicalised (`modules/canonical/*` + `resolved-settings.yaml` A.7-equivalent), but no wiki article ties vulnix cadence + nix-store-verify + patch SLAs together.
- Suggested fix: write a short "Vulnerability Management" article when vulnix actually ships; for now, retarget.
- Mechanical / judgement: judgement.

### Finding 21 — Accounts module has no wiki article

- Location: no `wiki/shared-controls/account-lifecycle.md` or `wiki/architecture/accounts-module.md`.
- Severity: gap.
- Why: ARCH-11 shipped `modules/accounts/default.nix` with a novel pattern (admin user declared in module, `hashedPassword = "!"`, quarterly access-review collector registered into ARCH-10). The only wiki touchpoint is `shared-controls-overview.md` control 15, which still credits stig-baseline (Finding 5). Raw note `raw/arch-11-account-lifecycle.md` is uncompiled.
- Suggested fix: compile `arch-11-account-lifecycle.md` into a new `shared-controls/account-lifecycle.md` during the next compile PR; cross-link from `evidence-generation.md` (new access-review collector row), `shared-controls-overview.md:23`, and `meta-module.md` (new consumer).
- Mechanical / judgement: judgement (where does it live — shared-controls vs architecture?). Open question at bottom.

### Finding 22 — No article on the evidence collectors shipped by framework modules

- Location: `evidence-generation.md` describes the extension point but never enumerates which framework modules will land collectors.
- Severity: gap.
- Why: ARCH-11 added the first real downstream collector (`accessReview`); `evidence-generation.md:40-57` does not mention it. Future HIPAA/PCI/HITRUST modules will follow the same pattern — without a living list, each addition requires a prose rewrite.
- Suggested fix: add a "Registered collectors" section listing which module registers which key; make it the single source of collector inventory.
- Mechanical / judgement: mechanical (add a table; update on each framework PR).

### Finding 23 — No article on `services.complianceEvidence.collectors` from the access-review perspective

- Location: no wiki article covers the access-review collector path itself.
- Severity: gap (subset of Finding 22).
- Suggested fix: covered by the account-lifecycle article (Finding 21); cross-link.
- Mechanical / judgement: mechanical.

### Finding 24 — Threat model + data-flows articles don't mention the accounts module admin user

- Location: `wiki/architecture/threat-model.md`, `wiki/architecture/data-flows.md`.
- Severity: gap.
- Why: The single admin user key-only login is now the project's answer to "how does a human operator authenticate"; threat model should reference it explicitly (IA-2 / §164.308 path).
- Suggested fix: add one bullet under "Protected assets / adversary model" pointing at account-lifecycle article.
- Mechanical / judgement: mechanical.

### Finding 25 — `hitrust-corrections.md` is orphaned from topic `_index.md`

- Location: `wiki/compliance-frameworks/_index.md:7-9`.
- Severity: style.
- Why: The index lists only three articles; `hitrust-corrections.md` exists and is cross-linked from `master-review.md:59` but not from its own topic index.
- Suggested fix: add `- [[hitrust-corrections]] — HITRUST CSF v11 domain-count + terminology corrections` to the index.
- Mechanical / judgement: mechanical.

## 5. Raw-vs-wiki drift

Raw files that have been in the tree for > 1 compile cycle (still in `raw/` after PR #48 compiled the ARCH-10 material). **Do not compile in this audit.**

- `raw/arch-11-account-lifecycle.md` — dated 2026-04-24, drives Findings 1, 2, 5, 21, 24. Already a post-PR-#48 addition per task context.
- `raw/build-and-test-tooling-research.md` — dated 2026-04-24, contains the known-broken lanzaboote URL footnote (line 258). Also contains nixos-generators + runNixOSTest + nixos-anywhere + disko guidance that currently has zero wiki coverage.
- `raw/session-pause-2026-04-24-third.md` — dated 2026-04-24; session hand-off note, low wiki value but should be triaged for anything load-bearing.
- `raw/session-pause-2026-04-24-cont.md` and `raw/session-pause-2026-04-24.md` — earlier same-day pause notes; typically not compiled.
- `raw/arch-12-rag-data-flow.md`, `raw/arch-13-residual-risks-appendix.md` — dated 2026-04-24, landed pre-PR-#48 and ARE partly reflected in wiki (residual-risks-register.md, data-flows RAG section). Verify during next compile that nothing essential is still raw-only.
- `raw/ai-14-15-16-hitrust-rewrite.md` — 2026-04-24; HITRUST material partly in `hitrust-corrections.md` but Finding 25 and the Maturity Level constraint section may not be fully compiled.
- `raw/multi-agent-parallel-execution-lessons.md` — 2026-04-24; lessons 37 & 38 are compiled into `lessons-learned.md:57-58`. Nothing else pending unless a dedicated "agent orchestration" article is wanted (out of scope).

## 6. Broken or stale external references

### Finding 26 — Lanzaboote docs URL

- Location: `raw/build-and-test-tooling-research.md:258` (the raw note already flags the 404); no wiki article currently cites the broken URL.
- Severity: style (prophylactic).
- Why: Task brief flags `github.com/nix-community/lanzaboote/blob/master/docs/QUICK_START.md` as 404. Grep across `wiki/` finds no occurrences, which is good — the fix is to ensure the next compile of `build-and-test-tooling-research.md` lands the authoritative URL `https://nix-community.github.io/lanzaboote/` and not the broken one.
- Suggested fix: when compiling build-and-test tooling to wiki, use the github.io URL exclusively.
- Mechanical / judgement: mechanical.

### Finding 27 — `nixos-gotchas.md:98-100` cites a specific sops-nix SHA as "last known-good"

- Location: `wiki/nixos-platform/nixos-gotchas.md:~100`.
- Severity: stale-risk.
- Why: The SHA `3b4a369df9...` is presented as "last known-good point for nixos-24.11 as of 2026-04." Since today IS 2026-04-24, this is not yet stale, but it will go stale silently. No external URL to check, but the flake.lock is the authoritative answer.
- Suggested fix: replace the SHA with "see `flake.lock` input `sops-nix.rev`". Keeps the article self-healing.
- Mechanical / judgement: mechanical.

### Finding 28 — ci-gate key takeaway count mismatch

- Location: `wiki/architecture/ci-gate.md:62`.
- Severity: style.
- Why: Body lists 7 checks (`:11-19`) but Key Takeaway says "Five checks: nix flake check, nix eval toplevel, statix, deadnix, legacy-FHS grep." Missing: both FHS lint layers (broad vs narrow) counted separately, and the secrets-in-store leakage lint.
- Suggested fix: change to "Seven checks" and update the list, or collapse to "five categories: flake check, toplevel eval, anti-pattern lints, FHS lints, secret-leak lint."
- Mechanical / judgement: mechanical.

## Non-findings

Items specifically checked and found clean:

- `resolved-settings.yaml` and `modules/canonical/default.nix` agree on every auth value I spot-checked (password min length 15, history 24, max age 60, lockout 5/1800, session timeouts 600).
- `docs/residual-risks.md` contains exactly 9 rows (headings 1-9), matching the wiki's `residual-risks-register.md:32-42` table.
- `wiki/shared-controls/secrets-management.md` secret catalogue and rotation schedule are consistent with `modules/secrets/default.nix` (verified options.secrets.rotationDays, defaultSopsFile path, validateSopsFiles=false).
- sops-nix vs agenix is unambiguous across every wiki article touching secrets.
- `wiki/shared-controls/evidence-generation.md` cadence claims (weekly + on-rebuild) match `modules/audit-and-aide/evidence.nix` structure described in the raw note (not re-read here).
- No broken internal wiki links beyond Findings 15, 16 (dangling targets) and Finding 14 (prefix drift).
- No wiki article cites the known-broken lanzaboote URL.
- `wiki/architecture/boot-integrity.md` priority-dance narrative matches `modules/stig-baseline/default.nix:99-106` (mkForce false inside the gated block).

## Open questions for human review

- **Accounts module article location.** Should `arch-11-account-lifecycle` compile into `shared-controls/account-lifecycle.md` (matches control 15) or `architecture/accounts-module.md` (matches how `meta-module.md` and `boot-integrity.md` are filed)? The boot-integrity/meta-module precedent suggests `architecture/`; the shared-controls precedent suggests `shared-controls/`. Picking `shared-controls/` is slightly better because the control-number mapping already exists.
- **Stub modules — delete rows, mark, or keep?** `flake-modules.md`, `cross-framework-matrix.md`, and `shared-controls-overview.md` all reference `gpu-node`, `lan-only-network`, `agent-sandbox`, `ai-services` as if they have shipped controls. They are stubs (one-file, comment-only). Three options: (a) drop rows entirely, (b) mark with a `[stub]` tag, (c) keep and trust the reader. Pick a policy before the next compile.
- **`_graph.md` scope.** Does the graph stay "four hubs" or grow to reflect the ARCH-era reality? A single-glance graph has real value; a 20-node graph stops being a graph.
- **`incident-response-hooks` and `vulnerability-management` articles — pre-ship or post-ship?** Pattern elsewhere has been "wiki article compiled from raw when the module lands." These two have no corresponding module yet. Confirm whether we want placeholder articles + disclaimer, or dangling-link-now + article-at-ship.
- **Password max age STIG vs NIST tension.** `docs/resolved-settings.yaml:335-337` notes NIST 800-63B disagrees with STIG's 60-day rotation. Should this tension also be called out in the wiki article, or is the YAML the right single place for it? Current wiki coverage is silent (Finding 10).
