# Nix Implementation Patterns

Concrete NixOS configuration patterns for building the flake modules. These are the actual code patterns extracted from the STIG, NIST, and HIPAA PRDs, organized by owning module.

## stig-baseline: Boot Security

### Secure Boot via Lanzaboote
```nix
boot.loader.systemd-boot.enable = lib.mkForce false;
boot.lanzaboote = { enable = true; pkiBundle = "/etc/secureboot"; };
```
Requires separate flake input. If not using lanzaboote, verify Secure Boot manually at firmware level.

### Bootloader + Emergency Mode
```nix
boot.loader.systemd-boot.editor = false;           # Prevent boot param modification
systemd.ctrlAltDelUnit = "";                        # Disable Ctrl-Alt-Del reboot
systemd.services."emergency".serviceConfig.ExecStart = [ "" "${pkgs.util-linux}/bin/sulogin" ];
systemd.services."rescue".serviceConfig.ExecStart = [ "" "${pkgs.util-linux}/bin/sulogin" ];
```
Without emergency mode auth (CAT I), anyone with console access gets a root shell.

### Filesystem Mount Hardening
```nix
fileSystems."/tmp"     = { device = "tmpfs"; fsType = "tmpfs"; options = [ "nosuid" "nodev" "noexec" "size=4G" ]; };
fileSystems."/dev/shm" = { device = "tmpfs"; fsType = "tmpfs"; options = [ "nosuid" "nodev" "noexec" ]; };
fileSystems."/var/tmp" = { device = "tmpfs"; fsType = "tmpfs"; options = [ "nosuid" "nodev" "noexec" "size=2G" ]; };
```

### DMA Protection
```nix
boot.kernelParams = [ "intel_iommu=on" "iommu=pt" ];  # AMD: "amd_iommu=on"
```
Thunderbolt/USB4 DMA attacks can bypass all OS access controls without IOMMU.

## stig-baseline: Kernel Hardening (Full sysctl)

All values set once in `stig-baseline`. No other module should declare `boot.kernel.sysctl`.

### Network Stack
| Parameter | Value | Why |
|---|---|---|
| `net.ipv4.conf.all.accept_redirects` | 0 | Prevent MITM |
| `net.ipv4.conf.all.send_redirects` | 0 | Not a router |
| `net.ipv4.conf.all.accept_source_route` | 0 | Block source-routed packets |
| `net.ipv4.ip_forward` | 0 | Not a router |
| `net.ipv4.tcp_syncookies` | 1 | SYN flood protection |
| `net.ipv4.conf.all.log_martians` | 1 | Log impossible source addresses |
| `net.ipv4.icmp_echo_ignore_broadcasts` | 1 | Ignore broadcast ICMP |
| `net.ipv4.conf.all.rp_filter` | 1 | Reverse path filtering |
| `net.ipv6.conf.all.accept_ra` | 0 | No router advertisements |
| `net.ipv4.tcp_timestamps` | 0 | Prevent info leakage |
| `net.ipv4.tcp_rfc1337` | 1 | TIME-WAIT assassination protection |
| `net.core.bpf_jit_harden` | 2 | JIT compiler hardening |

### Kernel
| Parameter | Value | Why |
|---|---|---|
| `kernel.randomize_va_space` | 2 | Max ASLR (CAT I) |
| `kernel.dmesg_restrict` | 1 | Root-only dmesg |
| `kernel.kptr_restrict` | 2 | Hide kernel pointers |
| `kernel.yama.ptrace_scope` | 2 | Restrict ptrace |
| `kernel.unprivileged_bpf_disabled` | 1 | No unprivileged BPF |
| `kernel.perf_event_paranoid` | 3 | Restrict perf events |
| `kernel.sysrq` | 0 | Disable SysRq |
| `kernel.core_pattern` | `\|/bin/false` | No core dumps |
| `kernel.panic` | 60 | Auto-reboot on panic |
| `kernel.panic_on_oops` | 1 | Treat oops as panic |
| `kernel.io_uring_disabled` | 2 | Disable io_uring (exploit vector) |
| `fs.suid_dumpable` | 0 | No SUID core dumps |
| `fs.protected_hardlinks` | 1 | Hardlink protection |
| `fs.protected_symlinks` | 1 | Symlink protection |
| `dev.tty.ldisc_autoload` | 0 | Restrict TTY line disciplines |

### Boot Parameters
```nix
boot.kernelParams = [
  "kexec_load_disabled=1"    # No runtime kernel replacement
  "slab_nomerge"             # SLAB hardening
  "init_on_alloc=1"          # Zero pages on allocation
  "init_on_free=1"           # Zero pages on free
  "page_alloc.shuffle=1"     # Page allocation randomization
  "vsyscall=none"            # Disable legacy interface
  "intel_iommu=on"           # DMA protection
  "iommu=pt"                 # Passthrough mode
];
```

## stig-baseline: PAM Configuration

### Critical Rule
NixOS PAM uses either **structured options** OR **`.text` override** — NEVER both on the same service. They are mutually exclusive.

- **`.text`** for login/su/sudo — needs precise faillock module ordering
- **Structured options** for sshd — just needs MFA via `googleAuthenticator.enable`

### Password Quality (`/etc/security/pwquality.conf`)
```
minlen=15  dcredit=-1  ucredit=-1  ocredit=-1  lcredit=-1
minclass=4  difok=8  maxrepeat=3  maxclassrepeat=4
dictcheck=1  usercheck=1
```

### login.defs Override
Use `lib.mkForce` to override NixOS shadow package values:
```nix
environment.etc."login.defs" = {
  source = lib.mkForce (pkgs.writeText "login.defs" ''
    UMASK 077
    PASS_MAX_DAYS 60
    PASS_MIN_DAYS 1
    HOME_MODE 0700
    ENCRYPT_METHOD SHA512
  '');
};
```

## stig-baseline: Sudo

```nix
security.sudo = {
  wheelNeedsPassword = true;    # CAT I: no NOPASSWD
  execWheelOnly = true;
  extraConfig = ''
    Defaults log_input, log_output
    Defaults iolog_dir=/var/log/sudo-io
    Defaults timestamp_timeout=5
    Defaults secure_path="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"
    Defaults env_reset
  '';
};
```
Note the NixOS-specific `secure_path` — uses `/run/current-system/sw/bin`, not `/usr/bin`.

## ai-services: Ollama GPU Device Access

Ollama needs explicit NVIDIA device access while maintaining strict sandboxing:
```nix
systemd.services.ollama.serviceConfig = {
  PrivateDevices = false;  # Must be false for GPU
  DeviceAllow = [
    "/dev/nvidia0 rw"
    "/dev/nvidiactl rw"
    "/dev/nvidia-uvm rw"
    "/dev/nvidia-uvm-tools rw"
  ];
  ProtectProc = "invisible";
  ProcSubset = "pid";
};
```
All other services use `PrivateDevices = true` (no GPU access needed).

## agent-sandbox: Maximum Isolation via DynamicUser

The strongest isolation pattern — agent sees almost nothing:
```nix
systemd.services.agent-runner.serviceConfig = {
  DynamicUser = true;                    # Transient UID
  TemporaryFileSystem = "/:ro";          # Read-only root
  BindReadOnlyPaths = [
    "/nix/store"
    "/run/current-system/sw"
    "/etc/resolv.conf"
    "/etc/ssl/certs"
  ];
  ReadWritePaths = [ "/var/lib/agent-runner" ];
  MemoryDenyWriteExecute = true;         # Safe here — no CUDA
};
```
Only 4 paths are visible. Compare to Ollama which needs GPU device access and cannot use `MemoryDenyWriteExecute`.

## Key Takeaways

- `stig-baseline` owns ALL sysctl, boot params, and PAM config — no other module should declare these
- PAM `.text` vs structured options is a hard either/or — mixing them breaks auth
- Sudo `secure_path` must use NixOS paths, not traditional `/usr/bin`
- Ollama needs `PrivateDevices = false` + explicit `DeviceAllow` — unique among all services
- `DynamicUser = true` + `TemporaryFileSystem = "/:ro"` is the maximum isolation pattern
- See [[../compliance-frameworks/canonical-config-values]] for the resolved values these patterns implement
