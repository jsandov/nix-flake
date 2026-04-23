# NixOS Implementation Patterns — Concrete Config for the Flake

Source: prd-stig-disa.md, prd-nist-800-53.md, prd-hipaa.md, prd-hitrust.md

These are the actual Nix code patterns needed to build the flake modules, extracted from the STIG/NIST/HIPAA/HITRUST PRDs. Organized by the module that owns them.

## stig-baseline: Boot Security

### Secure Boot via Lanzaboote
```nix
boot.loader.systemd-boot.enable = lib.mkForce false;
boot.lanzaboote = { enable = true; pkiBundle = "/etc/secureboot"; };
```

### Bootloader + Emergency Mode
- boot.loader.systemd-boot.editor = false (prevent boot param modification)
- systemd.ctrlAltDelUnit = "" (disable Ctrl-Alt-Del reboot)
- Emergency/rescue mode: require sulogin (CAT I — without this, console = root shell)

### Filesystem Mount Hardening
/tmp, /dev/shm, /var/tmp all need: nosuid, nodev, noexec

### DMA Protection
boot.kernelParams: intel_iommu=on, iommu=pt (or amd_iommu=on)
Thunderbolt/USB4 DMA attacks bypass all OS access controls without IOMMU.

## stig-baseline: Kernel Hardening (Full sysctl)

### Network Stack (30+ params)
- Reject ICMP redirects, source-routed packets
- Disable IP forwarding, SYN cookies, martian logging
- Reverse path filtering, no router advertisements
- Disable TCP timestamps (info leakage), RFC 1337 protection
- BPF JIT hardening

### Kernel Security
- ASLR max (CAT I), restrict dmesg/kptr/ptrace/perf/BPF
- Disable SysRq, io_uring, SUID core dumps
- Protect hardlinks/symlinks/fifos
- Auto-reboot on panic, treat oops as panic
- Restrict TTY line disciplines

### Boot Parameters
- kexec_load_disabled=1, slab_nomerge, init_on_alloc/free=1
- page_alloc.shuffle=1, vsyscall=none

## stig-baseline: PAM Configuration

### Critical Rule
NixOS PAM: structured options OR .text override — NEVER both on same service.
- .text for login/su/sudo (complex faillock ordering)
- Structured options for sshd (MFA only)

### Password Quality
minlen=15, all 4 char classes required, difok=8, maxrepeat=3, dictcheck=1

### login.defs
Use lib.mkForce to override NixOS shadow package values.
UMASK 077, PASS_MAX_DAYS 60, HOME_MODE 0700, SHA512

## stig-baseline: Sudo
- wheelNeedsPassword = true (CAT I: no NOPASSWD)
- log_input, log_output to /var/log/sudo-io
- secure_path must use NixOS paths: /run/current-system/sw/bin
- timestamp_timeout=5, env_reset

## stig-baseline: SSH (STIG-Specific Additions)
Beyond Appendix A.4: AllowTcpForwarding=false, AllowAgentForwarding=false,
PermitTunnel=false, MaxAuthTries=3, LoginGraceTime=60, LogLevel=VERBOSE,
HostbasedAuthentication=false, IgnoreRhosts=true, StrictModes=true
Host keys: Ed25519 + RSA-4096 only

## ai-services: Ollama GPU Device Access
- PrivateDevices = false (required for GPU)
- DeviceAllow: /dev/nvidia0, /dev/nvidiactl, /dev/nvidia-uvm, /dev/nvidia-uvm-tools
- ProtectProc = "invisible", ProcSubset = "pid"
- All other services use PrivateDevices = true

## agent-sandbox: Maximum Isolation
- DynamicUser = true (transient UID)
- TemporaryFileSystem = "/:ro" (read-only root)
- BindReadOnlyPaths: only /nix/store, /run/current-system/sw, /etc/resolv.conf, /etc/ssl/certs
- MemoryDenyWriteExecute = true (safe here — no CUDA)
- Agent sees almost nothing

## HITRUST Corrections
- CSF v11 has 19 domains (00-18), not 14
- Assessment tiers: e1 (44 statements), i1 (219), r2 (2000+)
- Maturity: Year 1 max Level 3, Year 2 Level 4, Level 5 not before Year 3
- Use "alternate controls" not "compensating controls" (PCI DSS term)
- Work from MyCSF portal, not summaries
