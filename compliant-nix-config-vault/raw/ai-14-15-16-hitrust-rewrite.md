# AI-14 + AI-15 + AI-16 — HITRUST PRD Rewrite (Raw Note)

**Bead:** `nf-kc3`
**Branch:** `feat/ai-14-15-16-hitrust-fixes`
**Date:** 2026-04-23
**Scope:** `docs/prd/prd-hitrust.md`

MASTER-REVIEW flagged three HITRUST issues. This PR fixes all three while preserving the existing working content of `prd-hitrust.md`. The document was already restructured into 19 domains (0–13) in a prior pass; the gap was dedicated sections for domains 14–18 (AI-14), a load-bearing Year-1 Level-3 cap (AI-15), and missing content for physical / incident / BCP / privacy (AI-16). This note captures what changed.

## Domain-mapping table — old 14-domain view → new 19-domain taxonomy (CSF v11)

| 19-domain number | 19-domain name | Where the content lived in the old 14-domain view / current file | Treatment in the rewrite |
|---|---|---|---|
| 00 | Information Security Management Program | Domain 00 (already present) | Preserved unchanged |
| 01 | Access Control | Domain 01 (already present, with Mobile 01.x-y subset) | Preserved; Mobile subset promoted to dedicated Domain 17 with cross-ref |
| 02 | Human Resources Security | Domain 02 (already present, with Education 02.e) | Preserved; Education & Training promoted to dedicated Domain 15 with cross-ref |
| 03 | Risk Management | Domain 03 (already present) | Preserved |
| 04 | Security Policy | Domain 04 (already present) | Preserved |
| 05 | Organization of Information Security | Domain 05 (already present, with Third-party 05.i-k) | Preserved; Third-party subset promoted to dedicated Domain 16 with cross-ref |
| 06 | Compliance | Domain 06 (already present) | Preserved |
| 07 | Asset Management | Domain 07 (already present) | Preserved |
| 08 | Physical and Environmental Security | Domain 08 (present, thin) | **Expanded** — added explicit residual-risks row 1 (live-memory ePHI) cross-ref and reframed as operator-declared organisational compensating controls for `physical-access` out-of-scope threat |
| 09 | Communications and Operations Management | Domain 09 (large shared block — auditd, firewall, TLS, config mgmt, malware, wireless subset, media) | Preserved as the authoritative Nix code block. Audit-logging and wireless subsets are now also referenced from Domains 14 and 18 |
| 10 | Info Systems Acquisition, Development, and Maintenance | Domain 10 (already present) | Preserved |
| 11 | Information Security Incident Management | Domain 11 (present, thin) | **Expanded** — added detection-and-escalation pipeline: `canonical.logRetention.journalForwardToSyslog = true` to SIEM, `notify-admin@<tag>.service` canonical template, on-call step explicitly deferred to `/docs/policies/incident-response-plan.md` |
| 12 | Business Continuity and Disaster Recovery | Domain 12 (titled "Business Continuity Management" — present, thin) | **Renamed** to match taxonomy + **expanded** — added "Recovery Strategy, RTO/RPO, and Restoration Cadence" section, updated BorgBackup snippet to reference canonical `backup/encryption-key` sops secret, explicit quarterly restoration drill |
| 13 | Privacy Practices | Domain 13 (present, thin) | **Expanded** — added HIPAA Privacy Rule alignment sub-section (§164.520 / 522 / 524 / 526 / 528), data minimisation + retention block with canonical `logRetention.aiDecisionLogs = "18month"`, right-to-access / right-to-deletion operational runbook hooks |
| 14 | Audit Logging and Monitoring | Buried inside Domain 09 §"09.aa–09.af" | **Created** dedicated section that references Domain 09's Nix block (no duplication), surfaces the canonical retention values, and adds evidence list |
| 15 | Education, Training, and Awareness | Buried inside Domain 02 §"02.e" | **Created** dedicated section that references Domain 02's banner/MOTD block, adds role-based training matrix (sysadmin / AI operator / all users), organisational processes |
| 16 | Third Party Assurance | Buried inside Domain 05 §"05.i-k" | **Created** dedicated section that references Domain 05's `nix.settings` + model-integrity-check block, adds system-specific third-party inventory with residual-risks row 3 cross-ref (trust-on-first-download) |
| 17 | Mobile Device Security | Buried inside Domain 01 §"01.x-y" | **Created** dedicated section with explicit N/A-at-server-tier scoping, server-side compensating controls (LAN-only firewall, key-only SSH, session timeout, TOTP MFA), alternate-control statement |
| 18 | Wireless Security | Buried inside Domain 09 §"09.m subset" | **Created** dedicated section with explicit N/A scoping, defence-in-depth wireless disablement, alternate-control statement |

## Where maturity claims were downgraded / capped (AI-15)

The existing file already had the primary Year-1 cap language (likely from a previous pass) — Year 1 explicitly targets Level 3 maximum. This PR hardens the cap and makes it assessor-visible:

- **Strengthened the header language** in "Maturity scoring constraints" — labelled the cap "(AI-15 cap)", rewrote the Year-1 bullet to make it a hard ceiling rather than a target, added the residual-risks row 9 cross-ref, flagged that Level-5 claims have historically caused r2 submission failures.
- **No per-domain Level-4/5 Year-1 claims were present** in the audited pre-existing text — the per-domain Implementation Level Targets tables only enumerate Level 1/2/3 (what each level would look like), and the Year 1 Assessment Targets table already sat at Level 3 max with HR at Level 2. This PR did not need to downgrade any existing Year-1 number.
- **New domains 14–18 Year-1 targets were added at Level 3 or below**:
  - 14 Audit Logging → Level 3 (Implemented)
  - 15 Education/Training → Level 2 (Procedure; full rollout pending)
  - 16 Third Party → Level 3 (Implemented)
  - 17 Mobile Device → N/A at server tier
  - 18 Wireless → N/A
- **Added a footnote under the Year-1 table** explicitly calling out the cap: "every entry above is at Level 3 or below. No Year-1 target in this PRD exceeds Level 3."
- **Year-2 targets were left in place at Level 4** for priority domains (00, 01, 03, 06, 09, 10, 11, 12) and new domain 14 (audit logging) — this matches residual-risks row 9 which promises Level-4 claims in Year 2 backed by the ARCH-10 evidence generator's 4 quarters of data. Year 2 is outside the AI-15 cap per the task brief.

**Count: 0 controls required downgrade from Level 4/5 to Level 3 for Year 1 in the pre-existing text.** The text already complied; this PR makes the cap load-bearing (explicit "hard ceiling" language + residual-risks cross-ref + per-table footnote) so subsequent edits cannot quietly regress it.

## What the four new / expanded domain sections contain

### Domain 08 — Physical and Environmental Security (expanded)
- Explicit reframing: `config.system.compliance.threatModel.outOfScope` includes `physical-access`, so Domain 08 is about **organisational compensating controls** the operator takes responsibility for (locked room, keyed access, environmental monitoring).
- Cross-reference to [[residual-risks.md]] row 1 (live-memory ePHI): physical access is the decisive control because without SEV-SNP / TDX / NVIDIA Confidential Computing, RAM and VRAM can be read by a physically-present attacker. AI-04 is the hardware-tier decision that would move the risk.
- Preserved the existing USBGuard / kernel module blacklist / LUKS defence-in-depth snippet.

### Domain 11 — Information Security Incident Management (expanded)
- New four-step detection-and-escalation pipeline: (1) local detection via auditd + AIDE, (2) journal forwarding via canonical `logRetention.journalForwardToSyslog = true` to a SIEM, (3) notification via canonical `notify-admin@%i.service` template (explicit note that `%i` is a systemd specifier, never shell `$1`), (4) on-call procedure deferred to `/docs/policies/incident-response-plan.md`.
- Preserved existing incident classification scheme table and evidence-collector systemd unit.

### Domain 12 — Business Continuity and Disaster Recovery (expanded + renamed)
- Renamed from "Business Continuity Management" to match the taxonomy.
- New "Recovery Strategy, RTO/RPO, and Restoration Cadence" section: daily Borg + weekly integrity check + quarterly restoration drill + annual bare-metal rebuild drill, evidence path under `/var/lib/hitrust-evidence/restoration-tests/<date>/`.
- BorgBackup snippet updated to reference the canonical sops secret `backup/encryption-key` (see `modules/secrets/default.nix`) rather than a hand-rolled `borg-passphrase` path.
- HIPAA §164.308(a)(7) + §164.310(a)(2)(i) cross-reference with explicit "HITRUST Domain 12 is the single source of truth for RTO/RPO numbers in this project."

### Domain 13 — Privacy Practices (expanded)
- New "HIPAA Privacy Rule Alignment" sub-section covering §164.520 / 522 / 524 / 526 / 528 with explicit treatments for right-of-access (agent-sandbox audit trail makes records findable), right-to-amendment/deletion (operator runbook), accounting of disclosures (scoped out because local-only inference — re-verify if RAG / external model providers added).
- New "Data Minimisation and Retention" block with canonical retention values: `logRetention.aiDecisionLogs = "18month"` and `logRetention.journalMaxRetention = "365day"`.
- Right-to-deletion runbook sketch: identify via audit trail → purge journal + agent artifacts → log the purge → document in DSR response record.
- Cross-reference to `docs/prd/prd-hipaa.md` and `docs/prd/prd-ai-governance.md`.

## Deliverables status

- [x] PRD rewritten in place (not a full rewrite; surgical restructure preserving existing content)
- [x] Raw note captured (this file)
- [ ] Branch creation / commit / push / PR — **blocked by bash sandbox restrictions** in this session; see report note to operator

## Verification TODOs for the follow-up operator

1. Re-verify the 19-domain list against live MyCSF (out-of-band fetch was blocked in this session).
2. Confirm `canonical.logRetention.journalForwardToSyslog = true` still reads line 185 of `modules/canonical/default.nix` — references cited in Domain 11 and Domain 14 depend on that path.
3. Confirm `"backup/encryption-key"` remains the canonical secret name declared in `modules/secrets/default.nix` — referenced by Domain 12.
4. Confirm the `notify-admin@` template unit still uses systemd `%i` per canonical A.15 — referenced by Domain 11.
