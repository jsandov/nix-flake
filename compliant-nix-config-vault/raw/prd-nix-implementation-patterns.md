# NixOS Implementation Patterns — Concrete Config for the Flake

Source: prd-stig-disa.md, prd-nist-800-53.md, prd-hipaa.md

These are the actual Nix code patterns needed to build the flake modules, organized by the module that owns them.

## stig-baseline: Boot Security

### Secure Boot via Lanzaboote
```nix
boot.loader.systemd-boot.enable = lib.mkForce false;
boot.lanzaboote = { enable = true; pkiBundle = "/etc/secureboot"; };
```

### Bootloader Protection
```nix
boot.loader.systemd-boot.editor = false; # Prevent boot param modification
```

### Filesystem Mount Hardening
```nix
fileSystems."/tmp" = { device = "tmpfs"; fsType = "tmpfs"; options = [ "nosuid" "nodev" "noexec" "size=4G" ]; };
fileSystems."/dev/shm" = { device = "tmpfs"; fsType = "tmpfs"; options = [ "nosuid" "nodev" "noexec" ]; };
fileSystems."/var/tmp" = { device = "tmpfs"; fsType = "tmpfs"; options = [ "nosuid" "nodev" "noexec" "size=2G" ]; };
```

### Emergency/Rescue Mode Auth (CAT I)
```nix
systemd.services."emergency".serviceConfig.ExecStart = [ "" "${pkgs.util-linux}/bin/sulogin" ];
systemd.services."rescue".serviceConfig.ExecStart = [ "" "${pkgs.util-linux}/bin/sulogin" ];
```

### DMA Protection via IOMMU
```nix
boot.kernelParams = [ "intel_iommu=on" "iommu=pt" ]; # AMD: "amd_iommu=on"
```

## stig-baseline: Kernel Hardening (Full sysctl Set)

### Network Hardening
- Reject ICMP redirects: all.accept_redirects = 0
- No send redirects: all.send_redirects = 0
- Reject source-routed packets: all.accept_source_route = 0
- Disable IP forwarding: ip_forward = 0
- SYN cookies: tcp_syncookies = 1
- Log martian packets: all.log_martians = 1
- Ignore ICMP broadcast: icmp_echo_ignore_broadcasts = 1
- Reverse path filtering: all.rp_filter = 1
- No IPv6 router ads: all.accept_ra = 0
- Disable TCP timestamps: tcp_timestamps = 0
- TIME-WAIT protection: tcp_rfc1337 = 1

### Kernel Hardening
- ASLR max: randomize_va_space = 2 (CAT I)
- Restrict dmesg: dmesg_restrict = 1
- Hide kernel pointers: kptr_restrict = 2
- ptrace scope: yama.ptrace_scope = 2
- Disable unprivileged BPF: unprivileged_bpf_disabled = 1
- Restrict userfaultfd: vm.unprivileged_userfaultfd = 0
- Perf paranoid: perf_event_paranoid = 3
- No SUID core dumps: fs.suid_dumpable = 0
- Disable SysRq: sysrq = 0
- Protect hardlinks/symlinks/fifos/regular: fs.protected_* = 1/2
- No core dumps: core_pattern = "|/bin/false"
- Auto-reboot on panic: panic = 60, panic_on_oops = 1
- Disable io_uring: io_uring_disabled = 2
- BPF JIT hardening: net.core.bpf_jit_harden = 2
- Restrict TTY line disciplines: dev.tty.ldisc_autoload = 0
- Minimal printk: "3 3 3 3"

### Boot Parameters
- kexec_load_disabled=1 (no runtime kernel replacement)
- slab_nomerge, init_on_alloc=1, init_on_free=1 (SLAB hardening)
- page_alloc.shuffle=1 (randomization)
- vsyscall=none (disable legacy interface)

## stig-baseline: PAM Configuration

### Critical PAM Note
NixOS PAM uses either structured options OR `.text` override — NEVER both on the same service. Use `.text` for login/su/sudo (complex faillock ordering). Use structured options for sshd (MFA only).

### Faillock Config
- deny=5, unlock_time=900, fail_interval=900, even_deny_root

### Password Quality (pwquality.conf)
- minlen=15, dcredit=-1, ucredit=-1, ocredit=-1, lcredit=-1
- minclass=4, difok=8, maxrepeat=3, maxclassrepeat=4
- dictcheck=1, usercheck=1

### login.defs Override
Use `lib.mkForce` to override NixOS shadow package managed values:
- UMASK 077, PASS_MAX_DAYS 60, PASS_MIN_DAYS 1, PASS_MIN_LEN 15
- HOME_MODE 0700, ENCRYPT_METHOD SHA512

## stig-baseline: Sudo Hardening

- wheelNeedsPassword = true (CAT I: no NOPASSWD)
- Log all I/O: log_input, log_output, iolog_dir=/var/log/sudo-io
- timestamp_timeout=5
- secure_path restricted to NixOS paths: /run/current-system/sw/bin
- env_reset enabled

## stig-baseline: SSH Hardening (Additional STIG-Specific)

Beyond canonical config (Appendix A.4), STIG adds:
- AllowTcpForwarding = false
- AllowAgentForwarding = false
- PermitTunnel = false
- MaxAuthTries = 3
- LoginGraceTime = 60
- HostbasedAuthentication = false
- IgnoreRhosts = true
- StrictModes = true
- LogLevel = "VERBOSE"
- Host keys: Ed25519 + RSA-4096 only

## ai-services: Ollama systemd Service (Full STIG Pattern)

Key details not in the wiki yet:
- DeviceAllow for NVIDIA: /dev/nvidia0, /dev/nvidiactl, /dev/nvidia-uvm, /dev/nvidia-uvm-tools
- PrivateDevices = false (required for GPU access)
- ProtectProc = "invisible", ProcSubset = "pid"
- ReadOnlyPaths includes /etc/ssl/certs
- HOME env var set to /var/lib/ollama

## agent-sandbox: Maximum Isolation Pattern

Key details not in wiki:
- DynamicUser = true (transient UID for maximum isolation)
- TemporaryFileSystem = "/:ro" (read-only root)
- BindReadOnlyPaths for only: /nix/store, /run/current-system/sw, /etc/resolv.conf, /etc/ssl/certs
- This creates a minimal filesystem view — agent sees almost nothing

## HITRUST: Corrected Domain Structure

HITRUST CSF v11 has 19 domains (00-18), not 14:
- 00: Information Security Management Program
- 01: Access Control
- 02: Human Resources Security
- 03: Risk Management
- 04: Security Policy
- 05: Organization of Information Security
- 06: Compliance
- 07: Asset Management
- 08: Physical and Environmental Security
- 09: Communications and Operations Management
- 10: Information Systems Acquisition, Development, and Maintenance
- 11: Information Security Incident Management
- 12: Business Continuity Management
- 13: Privacy Practices
- 14-18: Additional domains in v11

### Assessment Tiers
- e1 (Essentials): 44 requirement statements — fully met by flake
- i1 (Implemented): 219 statements — primary target
- r2 (Risk-based): 2000+ statements — stretch, needs external assessor

### Maturity Constraints
- Year 1: Level 3 (Implemented) max for all domains
- Year 2: Level 4 (Measured) for priority domains
- Level 5 (Managed): NOT achievable before Year 3
- Having auditd running = Level 3. Quarterly metric reports reviewed by management = Level 4.
