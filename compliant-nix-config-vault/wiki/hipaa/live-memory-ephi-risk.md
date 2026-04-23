# Live Memory ePHI Risk

**This is the single most significant residual risk in the entire system.**

## The Problem

During model inference, ePHI exists **unencrypted in system RAM and GPU VRAM**. LUKS full-disk encryption provides **ZERO protection** for data in memory on a running system. Once the volume is unlocked at boot, all data read from disk into RAM is decrypted.

Any process with sufficient privileges (or any kernel exploit) can read ePHI directly from memory.

## HITECH Safe Harbor Does NOT Apply

The encryption safe harbor (45 CFR §164.402(2)) covers ePHI encrypted on storage media. It does **NOT** cover ePHI resident in memory of a running system. If an attacker extracts ePHI from RAM/VRAM on a live system — even one with LUKS — breach notification is required.

## Mitigation Options

### Hardware Memory Encryption (Preferred)
- **AMD SEV-SNP** — per-VM memory encryption (EPYC processors)
- **Intel TDX** — similar for Intel (4th Gen Xeon+)
- Consumer/workstation hardware typically does NOT support these

### Software/Operational Mitigations
- Minimize ePHI retention in context windows
- Session-level clearing after each ePHI request
- Disable or encrypt swap
- Disable core dumps: `systemd.coredump.extraConfig = "Storage=none"` + `kernel.core_pattern = "|/bin/false"`
- Physical security for the running server
- `kernel.yama.ptrace_scope = 2` to prevent memory inspection
- Minimize accounts/processes that could read arbitrary memory

## Accepted Risk Documentation

If hardware memory encryption is unavailable (expected for workstation hardware), this must be documented as an **accepted risk** with compensating controls:

1. Physical access restricted
2. No remote root, SSH key-only + MFA
3. Inference services run under dedicated unprivileged users with systemd sandboxing
4. ptrace protection enabled
5. Core dumps disabled system-wide
6. Swap encrypted or disabled
7. Auditd monitors for privilege escalation
8. LAN-only network reduces remote exploitation surface

**Must be explicitly acknowledged in the organization's risk analysis and reviewed at each periodic evaluation.**

## Key Takeaways

- LUKS protects data at rest — it does nothing for data in live memory
- GPU VRAM is also unencrypted and not addressable by NixOS config
- This risk must be formally accepted and documented, not hand-waved
- See [[ephi-data-flow]] for controls at each stage of ePHI movement
- See [[ai-security/ai-security-residual-risks]] for related CUDA/VRAM limitations
