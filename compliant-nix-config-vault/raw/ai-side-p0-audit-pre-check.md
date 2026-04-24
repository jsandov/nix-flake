# AI-side P0 audit — pre-check result

Pattern 3 (pre-check TODO status with grep) applied to the six AI-side broken-Nix P0s. Result: all six are satisfied by current PRD state. Earlier sweeps (ARCH-05, ARCH-06, INFRA-03, INFRA-01+02) preemptively fixed every broken snippet the AI TODOs targeted.

## The six TODOs

| ID | Target pattern | Current state |
|---|---|---|
| AI-01 | `MemoryDenyWriteExecute = true` on Ollama / CUDA services | No Ollama service block sets it. Every snippet has a "DO NOT ENABLE" warning comment. Canonical table row (`prd.md` A.3) names the two-list carve-out. |
| AI-02 | `WatchdogSec=300` on Ollama service | No Ollama block sets it. `prd-ai-governance.md` §2.5 documents the sd_notify incompatibility and ships a replacement `ollama-health` timer that hits the `/api/tags` endpoint every 5 minutes. |
| AI-03 | `ai-model-fetch` script using `find -name "*.bin"` | Script at `prd-ai-governance.md:1270` already uses content-addressed blob paths (`/var/lib/ollama/models/blobs/sha256-<hex>`), reads the Ollama manifest to find the correct layer digest, and converts `sha256:abc...` to `sha256-abc...` filenames. |
| AI-05 | Missing core-dump disable | Canonical `nixosOptions.coredumpStorage = "none"` + `coredumpKernelPattern = "\|/bin/false"` already set. Implementation snippets in `prd-stig-disa.md:190` and `prd-hipaa.md:121` match. |
| AI-06 | `OLLAMA_HOST = "0.0.0.0:11434"` | Every current `OLLAMA_HOST` reference is `127.0.0.1`. The only `0.0.0.0` mentions are in MASTER-REVIEW historical findings. |
| AI-07 | `OLLAMA_NOPRUNE=1` framed as security control | No current snippet sets it as a security control. `prd-hipaa.md:976` has an explicit correction note ("was previously listed here as a security control... it is a storage management flag, not a security measure"). |

## Why the pre-check matters

Running the six greps took under two minutes. Opening six PRs to "fix" code that's already correct would have been hours of churn. Pattern 3 (lesson 29) paid for itself.

The slightly surprising sub-finding: **the PRDs have been maintained more carefully than MASTER-REVIEW suggests.** Several of the broken patterns MASTER-REVIEW catalogued were already fixed in the PRDs at some point before this session started — presumably during PRD authoring iterations that the review document didn't reflect.

**Follow-on rule:** MASTER-REVIEW findings are a *reliable upper bound* on broken Nix (they were observed at some point), not a *current state*. Always pre-check before treating them as live bugs.

## Small cleanup done in-pass

`prd-stig-disa.md:791` had a comment "Memory protections (MemoryDenyWriteExecute may conflict with CUDA JIT)". The language "may conflict" was weaker than the project convention ("must not be enabled on CUDA services"). Strengthened the comment to match the rest of the codebase — four-line comment pointing at the canonical rationale and the HIPAA deep-dive section. No code change, just prose.

## P0 queue after this PR

15 of 16 P0s complete. Only `AI-04` remains, and it is human-gated (SEV/TDX hardware decision vs signed-risk-acceptance letter). Cannot proceed without that decision.

## Suggested wiki compile targets

- `wiki/review-findings/lessons-learned.md` — extend entry 29 with a parenthetical about "MASTER-REVIEW findings are an upper bound on broken Nix, not current state." Worth capturing because it affects how any future review-driven work is planned.
- No new article needed. The general lesson lives in entry 29; this note is a concrete instance.
