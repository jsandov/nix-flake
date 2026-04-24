# HIPAA Key Findings

Commonly missed sections and technical safeguards for AI + NixOS.

## Sections Often Missed

### §164.316 — Policies and Documentation (Required)
All policies must be written and retained for **6 years**. The Git repo containing the flake serves as the documentation retention mechanism. Do NOT use force-push or filter-branch on branches with policy docs.

### §164.524/526/528 — Privacy Rule Individual Rights
- **Right of Access (§164.524):** Patients can request what data was processed. Requires structured logging with hashed patient identifiers and query capability.
- **Right of Amendment (§164.526):** Patients can request correction of inaccurate ePHI in RAG stores. Requires app-layer support for modifying/annotating RAG data.
- **Accounting of Disclosures (§164.528):** Must log every disclosure with date, recipient, description, purpose. 6-year retention.

### Breach vs. Security Incident Definitions
Must be defined specifically for this system. A breach includes confirmed unauthorized access to ePHI directories, memory extraction, data exfiltration, unauthorized model disclosure. Failed SSH logins are security incidents, not breaches.

## BAA Analysis

| Component | BAA Required? |
|---|---|
| Ollama (local) | No — open source, local, no data leaves host |
| Model providers | Generally no — weights downloaded once, run locally |
| Hardware vendor (on-site maintenance) | Possibly — if they access server with ePHI |
| Contractors with system access | Yes, if accessing ePHI |
| Backup storage provider | Yes, if off-site |
| Cloud model APIs (if ever added) | **Yes** — BAA required before any ePHI transmitted |

## Technical Safeguards Highlights

### Emergency Access (§164.312(a)(2)(ii))
Break-glass SSH key in physical safe. Emergency account in flake with auditd alerting on any use.

### Automatic Logoff (§164.312(a)(2)(iii))
SSH: `ClientAliveInterval=600`, `ClientAliveCountMax=0`. Console: `TMOUT=600; readonly TMOUT`.

### Encryption at Rest (§164.312(a)(2)(iv))
LUKS2 AES-256-XTS. Swap must also be encrypted. See [[../compliance-frameworks/canonical-config-values]].

### Backup (§164.308(a)(7))
BorgBackup with repokey-blake2 encryption for ePHI data directories. Daily schedule, 7/4/12 prune.

### Emergency Mode
Separate flake output (`ai-server-emergency`) with only stig-baseline + lan-only-network + audit-and-aide — AI services excluded.

## Key Takeaways

- HIPAA adds ePHI-specific requirements beyond what STIG/NIST already require
- The biggest additions: [[live-memory-ephi-risk|live memory risk]], BAA analysis, breach notification, privacy rule rights, documentation retention
- Ollama has no authentication — it must be behind an authenticated proxy, never directly accessible on LAN
- `OLLAMA_NOPRUNE=1` is NOT a security control — it's a storage management flag
- rsyslog log forwarding must use TLS (RELP) — cleartext log transmission violates §164.312(e)
