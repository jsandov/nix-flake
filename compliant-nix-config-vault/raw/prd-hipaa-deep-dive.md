# HIPAA Deep Dive — Key Findings for AI + NixOS

Source: prd-hipaa.md

## Critical Risk: Live Memory ePHI Exposure

**This is the single most significant risk in the entire system.**

During inference, ePHI exists **unencrypted in RAM and GPU VRAM**. LUKS full-disk encryption provides **ZERO protection** for data in memory on a running system.

### HITECH Safe Harbor Does NOT Apply
The encryption safe harbor (45 CFR §164.402(2)) covers data at rest on encrypted media. It does **NOT** cover ePHI in memory of a running system. If an attacker extracts ePHI from RAM/VRAM, breach notification is required.

### Mitigation Options
- **Hardware memory encryption** (AMD SEV-SNP or Intel TDX) — preferred but unlikely on workstation hardware
- **Minimize ePHI retention in context windows** — smallest necessary context
- **Session-level clearing** — null out prompt buffers after each request
- **Disable swap or encrypt it** — prevent memory writes to disk
- **Disable core dumps** — `systemd.coredump.extraConfig = "Storage=none"` + `kernel.core_pattern = "|/bin/false"`
- **Physical security** — restrict access to running server
- **ptrace protection** — `kernel.yama.ptrace_scope = 2`

### Must Document as Accepted Risk
Risk must be explicitly acknowledged in the organization's risk analysis and reviewed at each periodic evaluation.

## ePHI Data Flow Through AI System

Seven stages, each requiring specific controls:

1. **Prompt Ingestion** — TLS, auth, access logging, input validation
2. **RAG Context Retrieval** — filesystem ACL, encryption at rest, audit trail, minimum necessary
3. **Model Inference** — memory isolation, swap encryption, no telemetry, core dump disabled
4. **Agent Actions** — sandboxed execution, tool allowlisting, write path restriction, approval gates
5. **Output Delivery** — TLS, response logging, access control verification
6. **Log Persistence** — encrypted storage, restricted access, retention policy, redaction strategy
7. **Inter-Process Communication** — Unix socket permissions, shared memory isolation, D-Bus policy

## MemoryDenyWriteExecute + CUDA Incompatibility

CUDA JIT compilation requires W+X memory. Setting `MemoryDenyWriteExecute=true` on Ollama **crashes GPU inference**.

**Apply to:** agent-runner, API proxy, monitoring services
**Do NOT apply to:** Ollama, any CUDA/GPU service

Compensating controls: SystemCallFilter, RestrictAddressFamilies, ProtectSystem=strict, NoNewPrivileges

## Model Context Window Persistence Risk

Ollama may cache conversation state between requests. ePHI from Patient A may still be in memory when Patient B's request arrives. Requires:
- Aggressive session timeouts
- Explicit session clearing after ePHI requests
- Per-patient session isolation at app layer

## Nix Store Leakage Warning

The Nix store is **world-readable** (0444/0555). Any secrets or ePHI-derived config that ends up in a store path is accessible to all users. Required mitigation: use sops-nix/agenix, never reference secrets directly in Nix expressions.

## Key HIPAA Sections Often Missed

- **§164.316 (Policies and Documentation)** — Required standard. All policies must be written and retained 6 years.
- **§164.524/526/528 (Privacy Rule Individual Rights)** — Right of access, amendment, accounting of disclosures for AI processing of ePHI
- **Breach vs. Security Incident definitions** — Must be defined specifically for this system
- **BAA analysis** — Ollama itself (no BAA needed), but hardware vendors, contractors with access, backup providers, VPN providers may need BAAs

## Borgbackup for ePHI Data

```nix
services.borgbackup.jobs.ephi-backup = {
  paths = [ "/var/lib/ai-services" "/var/lib/ollama" "/var/lib/agent-runner" "/var/log/ai-audit" ];
  encryption.mode = "repokey-blake2";
  startAt = "daily";
};
```
