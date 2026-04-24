# PRD Module: DISA STIG and Anduril NixOS STIG Compliance Mapping

## 1. Purpose and Scope

This document is a compliance-specific PRD module that maps the NixOS AI Agentic Server (defined in `prd.md`) to the Defense Information Systems Agency (DISA) Security Technical Implementation Guide (STIG) expectations and the Anduril NixOS STIG. It provides finding-area-by-finding-area technical specifications with complete NixOS configuration for each requirement.

The Anduril NixOS STIG extends the general-purpose DISA STIG model to NixOS-specific implementation patterns: declarative configuration as the enforcement mechanism, flake-based change control, and systemd-native service hardening. This document bridges both the general DISA expectations and the NixOS-specific implementation guidance.

### Relationship to Main PRD

The main PRD defines functional requirements, acceptance criteria, and a high-level cross-framework control matrix. This module provides the STIG-specific depth: every finding area is mapped to concrete NixOS configuration, severity classifications, evidence requirements, and cross-references to NIST 800-53 (covered in `prd-nist-800-53.md`), HIPAA (covered in `prd-hipaa.md`), and PCI DSS (covered in `prd-pci-dss.md`).

> **Canonical Configuration Values**: All resolved configuration values for this system are defined in `prd.md` Appendix A. When inline Nix snippets in this document specify values that differ from Appendix A, the Appendix A values take precedence. Inline Nix code in this module is illustrative and shows the STIG-specific rationale; the implementation flake uses only the canonical values.

### System Scope Summary

| Component | Ports / Interfaces | Flake Module |
|---|---|---|
| SSH (administration) | TCP 22, LAN interface only | `stig-baseline`, `lan-only-network` |
| Ollama (inference API) | TCP 11434, localhost only (Nginx TLS termination) | `ai-services`, `lan-only-network` |
| Application APIs | TCP 8000, LAN interface only | `ai-services`, `lan-only-network` |
| Agent runners | No listening ports; outbound restricted | `agent-sandbox` |
| AIDE / audit subsystem | No listening ports | `audit-and-aide` |
| GPU runtime (NVIDIA/CUDA) | No listening ports | `gpu-node` |

---

## 2. Severity Classification Key

All findings in this document are classified according to the DISA severity category system:

| Category | Label | Meaning | Remediation Timeline |
|---|---|---|---|
| **CAT I** | Critical | Directly exploitable vulnerability that could lead to unauthorized access, data loss, or system compromise. | Immediate -- must be resolved before production deployment. |
| **CAT II** | High | Significant security weakness that increases risk but may require additional conditions for exploitation. | Within 30 days of identification. |
| **CAT III** | Medium | Configuration weakness that does not directly lead to compromise but weakens the overall security posture. | Within 90 days of identification. |

---

## 3. Priority Matrix for Implementation Order

Implementation should proceed in the order below. Each phase addresses the highest-severity findings first, then builds supporting infrastructure.

| Phase | Finding Areas | Severity Focus | Rationale |
|---|---|---|---|
| **Phase 0: Boot Security** | Secure Boot, Bootloader Protection, Mount Hardening, Emergency Mode Auth | CAT I, CAT II | Boot-time security must be established before any runtime controls are meaningful. Secure Boot, bootloader passwords, and mount options prevent tampering at the earliest stage. |
| **Phase 1: Foundation** | Identification and Authentication, Access Control | CAT I, CAT II | Without authentication and access control, no other control is meaningful. SSH lockdown, sudo restriction, and PAM hardening are prerequisites. |
| **Phase 2: Visibility** | Audit and Accountability | CAT II | Audit infrastructure must be operational before configuration hardening so that all subsequent changes are logged. |
| **Phase 3: Hardening** | System and Communications Protection, FIPS Considerations | CAT I, CAT II | Kernel hardening, firewall lockdown, and cryptographic configuration reduce the attack surface. |
| **Phase 4: Integrity** | Configuration Management, System and Information Integrity | CAT II, CAT III | AIDE, ClamAV, USB controls, and update strategy provide ongoing assurance after the baseline is established. |
| **Phase 5: Notification** | Login Notification | CAT III | Banner configuration is low-risk and depends on SSH being already hardened in Phase 1. |

---

## 3A. Finding Area 0: Boot and Physical Security Hardening

**Severity**: CAT I (Secure Boot bypass, unprotected bootloader), CAT II (mount options, emergency mode, Ctrl-Alt-Del, core dumps).

**NIST 800-53 Cross-Reference**: SC-39, SI-7, AC-3, AC-6.

### 3A.1 UEFI Secure Boot Verification (CAT I)

UEFI Secure Boot ensures that only cryptographically signed bootloaders and kernels execute during the boot process. This is configured in firmware, not in NixOS, but the PRD requires it and the check procedure must be documented.

**Requirement**: UEFI Secure Boot MUST be enabled in the system firmware (BIOS/UEFI settings).

**Verification Procedure**:

```bash
# Check Secure Boot status from a running system
mokutil --sb-state
# Expected output: "SecureBoot enabled"

# Alternative check via kernel
cat /sys/firmware/efi/efivars/SecureBoot-*
# Or via bootctl:
bootctl status | grep "Secure Boot"
```

**NixOS Considerations**: NixOS supports Secure Boot via the `lanzaboote` project. If using `lanzaboote`, configure it as follows:

```nix
{
  # Secure Boot support via lanzaboote (requires separate flake input)
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/etc/secureboot";
  };
}
```

If not using `lanzaboote`, Secure Boot must be verified manually at the firmware level during deployment. Document the Secure Boot status as part of the deployment checklist.

### 3A.2 Bootloader Password Protection (CAT I)

The bootloader must be protected against unauthorized modification of boot parameters. An attacker with physical or console access could modify kernel parameters (e.g., `init=/bin/sh`) to bypass all authentication controls.

```nix
{
  # For systemd-boot: restrict editor access
  # systemd-boot does not support password protection natively, but disabling
  # the editor prevents modification of boot parameters at the boot menu.
  boot.loader.systemd-boot.editor = false;

  # For GRUB-based systems: set a bootloader password
  # boot.loader.grub = {
  #   enable = true;
  #   device = "/dev/sda";
  #   # GRUB password hash generated with: grub-mkpasswd-pbkdf2
  #   extraConfig = ''
  #     set superusers="admin"
  #     password_pbkdf2 admin grub.pbkdf2.sha512.10000.<hash>
  #   '';
  # };
}
```

### 3A.3 Filesystem Mount Hardening (CAT II)

Temporary filesystem mount points must have restrictive options to prevent execution of arbitrary code, setuid binaries, or device files from user-writable locations.

```nix
{
  # Harden /tmp -- prevent execution, setuid, and device files
  fileSystems."/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "nosuid" "nodev" "noexec" "size=4G" ];
  };

  # Harden /dev/shm -- shared memory must not allow execution
  fileSystems."/dev/shm" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "nosuid" "nodev" "noexec" ];
  };

  # Harden /var/tmp if it is a separate mount
  # If /var/tmp is not a separate mount, ensure it is symlinked to /tmp
  # or create it as a tmpfs:
  fileSystems."/var/tmp" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "nosuid" "nodev" "noexec" "size=2G" ];
  };
}
```

### 3A.4 Disable Ctrl-Alt-Del Reboot (CAT II)

The Ctrl-Alt-Del key combination must be disabled to prevent unauthorized reboots from the console, which could be used to interrupt services or boot into a modified configuration.

```nix
{
  # Disable Ctrl-Alt-Del reboot sequence
  systemd.ctrlAltDelUnit = "";

  # Alternative approach using target override:
  # systemd.targets."ctrl-alt-del" = { enable = false; };
}
```

### 3A.5 Emergency and Rescue Mode Authentication (CAT I)

Emergency and rescue modes must require root authentication. Without this, anyone with console access can obtain a root shell by booting into emergency or rescue mode.

```nix
{
  # Require authentication for emergency mode
  systemd.services."emergency".serviceConfig.ExecStart = [
    ""  # Clear the default ExecStart
    "${pkgs.util-linux}/bin/sulogin"
  ];

  # Require authentication for rescue mode
  systemd.services."rescue".serviceConfig.ExecStart = [
    ""  # Clear the default ExecStart
    "${pkgs.util-linux}/bin/sulogin"
  ];
}
```

### 3A.6 Core Dump Restrictions (CAT II)

Core dumps can contain sensitive data (passwords, cryptographic keys, PII) from process memory. They must be disabled system-wide.

```nix
{
  # Disable core dump storage via systemd-coredump
  systemd.coredump.extraConfig = "Storage=none";

  # Redirect core dumps to /bin/false via kernel
  boot.kernel.sysctl."kernel.core_pattern" = "|/bin/false";

  # PAM hard limit on core file size
  security.pam.loginLimits = [
    {
      domain = "*";
      type = "hard";
      item = "core";
      value = "0";
    }
  ];
}
```

### 3A.7 Thunderbolt/USB4 DMA Protection (CAT II)

Thunderbolt and USB4 ports support Direct Memory Access (DMA), which can be exploited by malicious devices to read or write system memory directly, bypassing all OS-level access controls. IOMMU must be enabled to contain DMA to authorized memory regions.

```nix
{
  # Enable IOMMU for DMA protection
  # Use intel_iommu=on for Intel systems, amd_iommu=on for AMD systems
  boot.kernelParams = [
    # For Intel systems:
    "intel_iommu=on"
    "iommu=pt"  # Passthrough mode for performance with IOMMU protection

    # For AMD systems (uncomment and comment out Intel lines):
    # "amd_iommu=on"
    # "iommu=pt"
  ];
}
```

### 3A.8 Evidence Generation: Boot Security

| Evidence Artifact | Description | Collection Method |
|---|---|---|
| Secure Boot status | Verify UEFI Secure Boot is enabled | `mokutil --sb-state` |
| Bootloader editor status | Verify boot parameter editing is disabled | `bootctl status`, check `editor` setting |
| Mount options | Verify nosuid/nodev/noexec on /tmp, /dev/shm | `mount \| grep -E '/tmp\|/dev/shm\|/var/tmp'` |
| Ctrl-Alt-Del status | Verify reboot on Ctrl-Alt-Del is disabled | `systemctl status ctrl-alt-del.target` |
| Emergency mode auth | Verify sulogin is required | `systemctl cat emergency.service` |
| Core dump config | Verify core dumps are disabled | `ulimit -c`, `cat /proc/sys/kernel/core_pattern`, `coredumpctl` |
| IOMMU status | Verify IOMMU is active | `dmesg \| grep -i iommu`, `cat /proc/cmdline` |

---

## 4. Finding Area 1: Identification and Authentication

**Severity**: CAT I (password auth enabled, root login permitted), CAT II (PAM misconfiguration, missing MFA, weak session controls).

**NIST 800-53 Cross-Reference**: IA-2, IA-2(1), IA-2(2), IA-4, IA-5, IA-5(1), IA-8, AC-7, AC-10, AC-11, AC-12.
**HIPAA Cross-Reference**: 164.312(d) -- Person or Entity Authentication.
**PCI DSS Cross-Reference**: Requirement 8 -- Identify Users and Authenticate Access.

### 4.1 SSH Key-Based Authentication Only (CAT I)

Password authentication and keyboard-interactive authentication must be disabled. Only public key authentication is permitted. Root login is prohibited entirely.

```nix
{
  # Canonical SSH config per prd.md Appendix A.4
  services.openssh = {
    enable = true;
    openFirewall = false;  # Firewall managed separately in lan-only-network module

    settings = {
      # CAT I: Disable all password-based authentication
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;

      # CAT I: Prohibit root login via any method
      PermitRootLogin = "no";

      # CAT II: Restrict to named admin users only
      AllowUsers = [ "admin" ];

      # CAT II: Disable unnecessary features
      X11Forwarding = false;
      AllowTcpForwarding = false;
      AllowAgentForwarding = false;
      PermitTunnel = false;

      # CAT II: Limit authentication attempts per connection
      MaxAuthTries = 3;

      # CAT II: Protocol hardening
      LoginGraceTime = 60;
      MaxStartups = "10:30:60";
      PermitEmptyPasswords = false;

      # NOTE: The "Protocol" option was removed in OpenSSH 7.6. NixOS ships
      # OpenSSH 9.x which only supports protocol version 2. Do NOT set
      # Protocol = 2; it will cause sshd to fail to start or emit errors.

      # CAT III: Disable host-based authentication
      HostbasedAuthentication = false;
      IgnoreRhosts = true;

      # CAT II: Strict mode checks file permissions on key files
      StrictModes = true;

      # CAT II: Log level sufficient for audit trail
      LogLevel = "VERBOSE";
    };

    # Host key algorithms -- restrict to strong keys
    hostKeys = [
      { type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }
      { type = "rsa"; bits = 4096; path = "/etc/ssh/ssh_host_rsa_key"; }
    ];
  };
}
```

### 4.2 PAM Configuration: Account Lockout and Password Complexity (CAT II)

Even though password login is disabled for SSH, PAM configuration is required for local console access, `su`, `sudo`, and potential future services. STIG requires faillock for account lockout and password complexity enforcement.

**NixOS PAM Note**: NixOS manages PAM through structured options in `security.pam.services`. When using `.text` to override the entire PAM stack, do NOT also use structured options like `googleAuthenticator.enable` on the same service, as they are mutually exclusive. The `.text` approach is used here for `login`, `su`, `sudo`, and `passwd` because these require precise control of the faillock module ordering. Services that only need MFA (like `sshd`) use structured options instead (see Section 4.3).

```nix
{
  security.pam.services = {
    # Apply faillock to login, su, sudo
    # NOTE: Using .text override for full PAM stack control with faillock ordering.
    # Do NOT mix .text with structured options (e.g., googleAuthenticator.enable)
    # on the same service -- they are mutually exclusive.
    login.text = ''
      # PAM configuration for local login
      auth     required       pam_faillock.so preauth silent deny=5 unlock_time=900 fail_interval=900
      auth     required       pam_unix.so try_first_pass
      auth     required       pam_faillock.so authfail deny=5 unlock_time=900 fail_interval=900
      auth     required       pam_faillock.so authsucc deny=5 unlock_time=900 fail_interval=900
      account  required       pam_faillock.so
      account  required       pam_unix.so
      password required       pam_pwquality.so retry=3 minlen=15 dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1 minclass=4 difok=8 maxrepeat=3 maxclassrepeat=4 dictcheck=1
      password required       pam_unix.so use_authtok shadow sha512 remember=5
      session  required       pam_limits.so
      session  required       pam_unix.so
    '';

    su.text = ''
      auth     required       pam_faillock.so preauth silent deny=5 unlock_time=900 fail_interval=900
      auth     sufficient     pam_unix.so try_first_pass
      auth     required       pam_faillock.so authfail deny=5 unlock_time=900 fail_interval=900
      account  required       pam_faillock.so
      account  required       pam_unix.so
      session  required       pam_unix.so
    '';

    sudo.text = ''
      auth     required       pam_faillock.so preauth silent deny=5 unlock_time=900 fail_interval=900
      auth     sufficient     pam_unix.so try_first_pass
      auth     required       pam_faillock.so authfail deny=5 unlock_time=900 fail_interval=900
      account  required       pam_faillock.so
      account  required       pam_unix.so
      session  required       pam_unix.so
    '';
  };

  # Password quality enforcement via pwquality
  # This sets /etc/security/pwquality.conf
  security.pam.services.passwd.text = ''
    password required pam_pwquality.so retry=3 minlen=15 dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1 minclass=4 difok=8 maxrepeat=3 maxclassrepeat=4 dictcheck=1
    password required pam_unix.so use_authtok shadow sha512 remember=5
  '';

  # Ensure the faillock directory exists and pwquality is available
  # NOTE: pkgs.pam does not exist in nixpkgs. The PAM library is part of the
  # base system and does not need explicit installation. Use pkgs.linux-pam
  # only if PAM development headers or tools are specifically needed.
  environment.systemPackages = with pkgs; [
    libpwquality
  ];

  # Faillock configuration file
  environment.etc."security/faillock.conf".text = ''
    # STIG: Account lockout after 5 failed attempts
    deny = 5
    # STIG: 15-minute lockout period (900 seconds)
    unlock_time = 900
    # Failure counting window
    fail_interval = 900
    # Log even successful authentications after failures
    audit
    # Do not lock root (root can only login at console, which requires physical access)
    even_deny_root
    root_unlock_time = 900
  '';

  # Password complexity via pwquality.conf
  environment.etc."security/pwquality.conf".text = ''
    # STIG: Minimum password length of 15 characters
    minlen = 15
    # STIG: At least 1 digit
    dcredit = -1
    # STIG: At least 1 uppercase letter
    ucredit = -1
    # STIG: At least 1 special character
    ocredit = -1
    # STIG: At least 1 lowercase letter
    lcredit = -1
    # STIG: Require all 4 character classes
    minclass = 4
    # STIG: At least 8 characters different from previous password
    difok = 8
    # STIG: No more than 3 consecutive identical characters
    maxrepeat = 3
    # STIG: No more than 4 consecutive characters from same class
    maxclassrepeat = 4
    # STIG: Check against dictionary
    dictcheck = 1
    # Reject passwords containing the username
    usercheck = 1
  '';
}
```

### 4.3 MFA for Privileged Remote Access (CAT I)

STIG requires multi-factor authentication for privileged remote access. The `pam_google_authenticator` module provides TOTP-based MFA for SSH sessions.

**NixOS PAM Note**: The `sshd` service uses structured PAM options (not `.text` override) because it does not require the complex faillock ordering used by `login`/`su`/`sudo`. Structured options and `.text` must not be mixed on the same service.

```nix
{
  # Install the Google Authenticator PAM module via structured options
  security.pam.services.sshd = {
    googleAuthenticator.enable = true;

    # Ensure MFA is required in addition to public key
    # The SSH server must be configured for AuthenticationMethods below
    rules.auth = {
      google_authenticator = {
        enable = true;
        order = 12000;  # After public key auth
        control = "required";
        modulePath = "${pkgs.google-authenticator}/lib/security/pam_google_authenticator.so";
        settings = {
          nullok = false;  # Do not allow users without MFA configured to bypass
        };
      };
    };
  };

  # SSH must require both publickey and keyboard-interactive (for TOTP)
  services.openssh.extraConfig = ''
    # CAT I: Require both public key AND TOTP for admin users
    AuthenticationMethods publickey,keyboard-interactive

    # Re-enable keyboard-interactive solely for the TOTP prompt
    # Password auth remains disabled -- PAM handles the TOTP challenge only
    KbdInteractiveAuthentication yes
    ChallengeResponseAuthentication yes
    # DEPRECATED in OpenSSH 8.7+ (NixOS ships 9.x). See prd.md Appendix A.4.
    # Use KbdInteractiveAuthentication only. Remove this line in implementation.
  '';

  # Ensure google-authenticator CLI is available for initial setup
  environment.systemPackages = [ pkgs.google-authenticator ];
}
```

**Operational Note**: Each admin user must run `google-authenticator` once to generate their TOTP secret and QR code. The resulting `~/.google_authenticator` file must have permissions `0400` owned by the user.

**Alternative**: For hardware token MFA, replace `pam_google_authenticator` with FIDO2/U2F via `pam_u2f`:

```nix
{
  security.pam.services.sshd.u2fAuth = true;

  # U2F key mappings
  environment.etc."u2f_mappings".text = ''
    admin:<key-handle-1>,<public-key-1>
  '';

  security.pam.u2f = {
    enable = true;
    authFile = "/etc/u2f_mappings";
    cue = true;  # Prompt user to touch the key
  };
}
```

### 4.4 Session Controls: Idle Timeout and Concurrent Sessions (CAT II)

```nix
{
  # SSH session idle timeout
  services.openssh.settings = {
    # CAT II: Terminate idle sessions after 600 seconds (10 minutes)
    ClientAliveInterval = 600;
    ClientAliveCountMax = 0;  # Disconnect immediately after one missed keepalive

    # CAT II: Limit concurrent sessions per connection
    MaxSessions = 3;
  };

  # Shell-level idle timeout via TMOUT
  environment.etc."profile.d/tmout.sh".text = ''
    # STIG: Automatic logout after 600 seconds of inactivity
    TMOUT=600
    readonly TMOUT
    export TMOUT
  '';

  # systemd-logind session controls
  services.logind.extraConfig = ''
    # Terminate idle sessions
    KillUserProcesses=yes
    # Idle action for console sessions
    IdleAction=lock
    IdleActionSec=600
  '';

  # PAM session limits for concurrent session control
  security.pam.loginLimits = [
    {
      domain = "*";
      type = "hard";
      item = "maxlogins";
      value = "3";
    }
    {
      domain = "admin";
      type = "hard";
      item = "maxlogins";
      value = "5";
    }
  ];
}
```

### 4.5 Account Management: Unique UIDs and Service Account Separation (CAT II)

```nix
{
  # Human accounts -- each with unique UID, home directory, and SSH key
  users.users.admin = {
    isNormalUser = true;
    uid = 1000;
    group = "admin";
    extraGroups = [ "wheel" ];
    home = "/home/admin";
    createHome = true;
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... admin@workstation"
    ];
    hashedPassword = null;  # No password -- SSH key + MFA only
  };

  users.groups.admin = {
    gid = 1000;
  };

  # Service accounts -- system users with no login shell, no home directory
  users.users.ollama = {
    isSystemUser = true;
    group = "ollama";
    shell = pkgs.shadow + "/bin/nologin";
    home = "/var/lib/ollama";
    createHome = false;  # Managed by the service
    description = "Ollama inference service account";
  };

  users.groups.ollama = {};

  users.users.ai-api = {
    isSystemUser = true;
    group = "ai-api";
    shell = pkgs.shadow + "/bin/nologin";
    home = "/var/lib/ai-api";
    createHome = false;
    description = "Application API service account";
  };

  users.groups.ai-api = {};

  users.users.agent = {
    isSystemUser = true;
    group = "agent";
    shell = pkgs.shadow + "/bin/nologin";
    home = "/var/lib/agent-runner";
    createHome = false;
    description = "Agent sandbox runner service account";
  };

  users.groups.agent = {};

  # Prevent direct login for service accounts via PAM
  # Service accounts have nologin shell and no password/key -- belt and suspenders
  users.mutableUsers = false;  # All account state must come from config
}
```

### 4.5 Evidence Generation: Identification and Authentication

| Evidence Artifact | Description | Collection Method |
|---|---|---|
| SSH configuration dump | Verify password auth disabled, root login disabled, MFA required | `sshd -T` output, or `cat /etc/ssh/sshd_config` |
| PAM configuration files | Verify faillock, pwquality, and MFA module presence | `cat /etc/pam.d/{login,sshd,su,sudo}` |
| Faillock status | Show locked accounts and failure counts | `faillock --user admin` |
| User account listing | Verify unique UIDs, service account separation | `cat /etc/passwd`, `cat /etc/group` |
| SSH authorized keys | Verify key-based auth is configured per user | `cat /home/admin/.ssh/authorized_keys` |
| MFA enrollment proof | Verify TOTP or FIDO2 is configured for each admin | `ls -la /home/admin/.google_authenticator` |
| Session timeout config | Verify TMOUT and SSH ClientAliveInterval | `echo $TMOUT`, `sshd -T \| grep clientalive` |
| NixOS generation config | Verify settings are declared in the active generation | `nixos-option services.openssh.settings` |

---

## 5. Finding Area 2: Access Control

**Severity**: CAT I (unrestricted sudo, NOPASSWD), CAT II (missing least privilege, weak file permissions).

**NIST 800-53 Cross-Reference**: AC-2, AC-3, AC-5, AC-6, AC-6(1), AC-6(9), AC-6(10), AC-17.
**HIPAA Cross-Reference**: 164.312(a)(1) -- Access Control.
**PCI DSS Cross-Reference**: Requirement 7 -- Restrict Access to System Components.

### 5.1 Sudo Restricted to Named Admin Users, No NOPASSWD (CAT I)

```nix
{
  security.sudo = {
    enable = true;

    # CAT I: Require password for all sudo operations -- no NOPASSWD
    wheelNeedsPassword = true;

    # Explicit rules -- only the admin user via the wheel group
    extraRules = [
      {
        groups = [ "wheel" ];
        commands = [
          {
            command = "ALL";
            options = [ "SETENV" "LOG_INPUT" "LOG_OUTPUT" ];
          }
        ];
      }
    ];

    # sudo logging configuration
    extraConfig = ''
      # STIG: Log all sudo commands
      Defaults log_input
      Defaults log_output
      Defaults iolog_dir=/var/log/sudo-io
      Defaults iolog_file=%{user}/%{command}/%{seq}

      # STIG: Require authentication timeout
      Defaults timestamp_timeout=5
      Defaults passwd_timeout=1

      # STIG: Restrict PATH for sudo commands
      Defaults secure_path="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"

      # STIG: Display warning banner
      Defaults lecture=always
      Defaults lecture_file=/etc/sudo_lecture

      # STIG: Prevent environment variable abuse
      Defaults env_reset
      Defaults env_check="DISPLAY XAUTHORIZATION LANG LANGUAGE LINGUAS LC_* TERM"
    '';
  };

  # Sudo lecture file
  environment.etc."sudo_lecture".text = ''
    WARNING: Privileged access is logged and monitored. Unauthorized use is prohibited.
  '';

  # Ensure sudo I/O log directory exists with proper permissions
  systemd.tmpfiles.rules = [
    "d /var/log/sudo-io 0700 root root -"
  ];
}
```

### 5.2 File Permissions: umask, Home Directories, Sensitive Files (CAT II)

```nix
{
  # System-wide umask of 077
  environment.etc."profile.d/umask.sh".text = ''
    umask 077
  '';

  # Login definitions -- umask and password aging.
  # NixOS 24.11+ ships structured `security.loginDefs.settings.*` options
  # that merge cleanly with the shadow-package-managed defaults. Prefer
  # them over `environment.etc."login.defs"` overrides (which, even with
  # `lib.mkForce`, conflict with NixOS PAM integration and lose fields
  # that the shadow package sets).
  security.loginDefs.settings = {
    # STIG: Default umask for user file creation
    UMASK = "077";
    # STIG: Password aging controls
    PASS_MAX_DAYS = 60;
    PASS_MIN_DAYS = 1;
    PASS_MIN_LEN = 15;
    PASS_WARN_AGE = 7;
    # STIG: Home directory permissions
    HOME_MODE = "0700";
    # STIG: UID/GID ranges
    UID_MIN = 1000;
    UID_MAX = 60000;
    SYS_UID_MIN = 100;
    SYS_UID_MAX = 999;
    GID_MIN = 1000;
    GID_MAX = 60000;
    # STIG: Encrypt passwords with SHA-512
    ENCRYPT_METHOD = "SHA512";
    # STIG: Create home directories on account creation
    CREATE_HOME = "yes";
  };

  # Restrict permissions on sensitive configuration files
  systemd.tmpfiles.rules = [
    # Home directories: 0700
    "d /home/admin 0700 admin admin -"

    # SSH directory and authorized_keys
    "d /home/admin/.ssh 0700 admin admin -"
    "f /home/admin/.ssh/authorized_keys 0600 admin admin -"

    # Audit log directory
    "d /var/log/audit 0700 root root -"

    # AIDE database
    "d /var/lib/aide 0700 root root -"

    # Service data directories
    "d /var/lib/ollama 0750 ollama ollama -"
    "d /var/lib/ai-api 0750 ai-api ai-api -"
    "d /var/lib/agent-runner 0750 agent agent -"
  ];

  # Ensure cron directories have restricted permissions
  environment.etc."cron.allow".text = "root\nadmin\n";
  environment.etc."at.allow".text = "root\nadmin\n";
}
```

### 5.3 Service Account Hardening: DynamicUser and Systemd Sandboxing (CAT II)

```nix
{
  # Ollama service with full systemd hardening
  systemd.services.ollama = {
    description = "Ollama Local Inference Server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      # Run as dedicated service user
      User = "ollama";
      Group = "ollama";

      # CAT II: Least privilege enforcement
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      ProtectProc = "invisible";
      ProcSubset = "pid";

      # Filesystem access
      ReadWritePaths = [ "/var/lib/ollama" ];
      ReadOnlyPaths = [ "/etc/ssl/certs" ];

      # Network restrictions -- bind to localhost only (Nginx handles LAN exposure)
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];

      # System call filtering
      SystemCallFilter = [
        "@system-service"
        "~@mount"
        "~@reboot"
        "~@swap"
        "~@clock"
        "~@cpu-emulation"
        "~@debug"
        "~@module"
        "~@obsolete"
        "~@raw-io"
      ];
      SystemCallArchitectures = "native";

      # Memory protections (MemoryDenyWriteExecute may conflict with CUDA JIT)
      LockPersonality = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      RestrictNamespaces = true;

      # Capability restrictions
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";

      # Device access -- GPU requires specific device access
      DeviceAllow = [
        "/dev/nvidia0 rw"
        "/dev/nvidiactl rw"
        "/dev/nvidia-uvm rw"
        "/dev/nvidia-uvm-tools rw"
      ];
      PrivateDevices = false;  # Must be false for GPU access

      ExecStart = "${pkgs.ollama}/bin/ollama serve";
      Restart = "always";
      RestartSec = 5;
    };

    environment = {
      # SECURITY: Bind to localhost only. Ollama is accessed via the Nginx TLS
      # reverse proxy (Section 8.2), which handles LAN-facing TLS termination.
      # Binding to 0.0.0.0 would expose the unencrypted API on all interfaces,
      # directly contradicting the LAN-only TLS requirement.
      OLLAMA_HOST = "127.0.0.1:11434";
      OLLAMA_MODELS = "/var/lib/ollama/models";
      HOME = "/var/lib/ollama";
    };
  };

  # Agent sandbox with maximum isolation
  systemd.services.agent-runner = {
    description = "Sandboxed AI Agent Runner";
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      # DynamicUser provides a transient UID -- maximum isolation
      DynamicUser = true;
      StateDirectory = "agent-runner";

      # Maximum sandboxing
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      PrivateNetwork = false;  # Needs LAN access to reach Ollama
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      ProtectProc = "invisible";
      ProcSubset = "pid";

      # Restrict filesystem to only the state directory
      ReadWritePaths = [ "/var/lib/agent-runner" ];
      TemporaryFileSystem = "/:ro";
      BindReadOnlyPaths = [
        "/nix/store"
        "/run/current-system/sw"
        "/etc/resolv.conf"
        "/etc/ssl/certs"
      ];

      # Network: allow only connections to localhost (Ollama) and LAN
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" ];
      IPAddressAllow = [ "127.0.0.0/8" "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" ];
      IPAddressDeny = "any";

      # Strict system call filter
      SystemCallFilter = [
        "@system-service"
        "~@mount"
        "~@reboot"
        "~@swap"
        "~@clock"
        "~@cpu-emulation"
        "~@debug"
        "~@module"
        "~@obsolete"
        "~@raw-io"
        "~@privileged"
      ];
      SystemCallArchitectures = "native";

      # Memory and capability restrictions
      MemoryDenyWriteExecute = true;
      LockPersonality = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      RestrictNamespaces = true;
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";

      # Resource limits
      LimitNOFILE = 1024;
      LimitNPROC = 64;
      MemoryMax = "4G";
      CPUQuota = "200%";

      # Timeout controls
      TimeoutStartSec = 30;
      TimeoutStopSec = 15;
      WatchdogSec = 300;

      ExecStart = "/run/current-system/sw/bin/agent-runner";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  # Application API service
  systemd.services.ai-api = {
    description = "AI Application API Server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "ollama.service" ];

    serviceConfig = {
      User = "ai-api";
      Group = "ai-api";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      PrivateDevices = true;
      ReadWritePaths = [ "/var/lib/ai-api" ];
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
      SystemCallFilter = [ "@system-service" "~@mount" "~@reboot" "~@swap" ];
      SystemCallArchitectures = "native";
      CapabilityBoundingSet = "";
      LockPersonality = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;

      ExecStart = "/run/current-system/sw/bin/ai-api-server --port 8000";
      Restart = "always";
      RestartSec = 5;
    };
  };
}
```

### 5.4 Evidence Generation: Access Control

| Evidence Artifact | Description | Collection Method |
|---|---|---|
| Sudo configuration | Verify no NOPASSWD, restricted to wheel group | `sudo -l`, `cat /etc/sudoers`, `cat /etc/sudoers.d/*` |
| Sudo I/O logs | Verify all privileged commands are logged | `ls -la /var/log/sudo-io/` |
| File permission audit | Verify umask, home dir permissions, sensitive file perms | `stat /home/admin`, `umask`, `find / -perm /4000 -type f` |
| Service unit analysis | Verify systemd sandboxing directives | `systemctl show ollama \| grep -E '(NoNew\|Protect\|Restrict\|Capability)'` |
| User account audit | Verify no shared accounts, proper group membership | `cat /etc/passwd`, `cat /etc/group`, `id admin` |
| SUID/SGID binary audit | Verify no unexpected setuid binaries | `find / -perm /6000 -type f 2>/dev/null` |

---

## 6. Finding Area 3: Audit and Accountability

**Severity**: CAT II (audit subsystem configuration), CAT III (log retention, log protection).

**NIST 800-53 Cross-Reference**: AU-2, AU-3, AU-3(1), AU-4, AU-5, AU-6, AU-7, AU-8, AU-9, AU-11, AU-12.
**HIPAA Cross-Reference**: 164.312(b) -- Audit Controls.
**PCI DSS Cross-Reference**: Requirement 10 -- Log and Monitor All Access.

### 6.1 Auditd with Comprehensive Rules (CAT II)

**NixOS Path Note**: NixOS does NOT have traditional Linux paths like `/usr/bin/sudo`, `/usr/sbin/useradd`, etc. Binaries live in `/nix/store` and are accessed via symlinks in `/run/current-system/sw/bin/` or `/run/wrappers/bin/` (for setuid wrappers). The audit rules below use NixOS-correct paths. For user/group management commands (`useradd`, `usermod`, `groupadd`, etc.), NixOS uses declarative user management -- these commands do not exist in the traditional sense. Instead, we monitor the files that change when users/groups are modified (via `nixos-rebuild`).

```nix
{
  security.auditd.enable = true;

  security.audit = {
    enable = true;
    # Do not lose events -- halt system if audit buffer is full (CAT II for DoD systems)
    failureMode = "panic";  # Options: silent, printk, panic

    rules = [
      # ===================================================================
      # SECTION 1: Self-protection -- protect the audit system itself
      # ===================================================================

      # Protect audit configuration from tampering
      "-w /etc/audit/ -p wa -k audit-config-change"
      "-w /etc/audit/audit.rules -p wa -k audit-config-change"
      "-w /etc/audit/auditd.conf -p wa -k audit-config-change"
      "-w /var/log/audit/ -p wa -k audit-log-tamper"

      # ===================================================================
      # SECTION 2: Authentication events
      # ===================================================================

      # Monitor login/logout events
      "-w /var/log/lastlog -p wa -k logins"
      "-w /var/log/wtmp -p wa -k logins"
      "-w /var/log/btmp -p wa -k logins"
      "-w /var/run/utmp -p wa -k session"

      # Monitor PAM configuration changes
      "-w /etc/pam.d/ -p wa -k pam-config-change"
      "-w /etc/security/ -p wa -k pam-config-change"

      # Monitor authentication-related files
      "-w /etc/shadow -p wa -k shadow-change"
      "-w /etc/passwd -p wa -k passwd-change"
      "-w /etc/group -p wa -k group-change"
      "-w /etc/gshadow -p wa -k gshadow-change"
      "-w /etc/login.defs -p wa -k login-defs-change"
      "-w /etc/securetty -p wa -k securetty-change"

      # Monitor SSH configuration
      "-w /etc/ssh/ -p wa -k sshd-config-change"
      "-w /etc/ssh/sshd_config -p wa -k sshd-config-change"

      # ===================================================================
      # SECTION 3: Privileged command execution (NixOS paths)
      # ===================================================================

      # NixOS uses /run/wrappers/bin/ for setuid-wrapped binaries.
      # Traditional paths like /usr/bin/sudo do NOT exist on NixOS.
      "-a always,exit -F path=/run/wrappers/bin/sudo -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged-sudo"
      "-a always,exit -F path=/run/wrappers/bin/su -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged-su"
      "-a always,exit -F path=/run/wrappers/bin/passwd -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged-passwd"
      "-a always,exit -F path=/run/wrappers/bin/chsh -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged-chsh"
      "-a always,exit -F path=/run/wrappers/bin/newgrp -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged-newgrp"

      # Monitor chage if present (may be at /run/current-system/sw/bin/chage)
      "-a always,exit -F path=/run/current-system/sw/bin/chage -F perm=x -F auid>=1000 -F auid!=4294967295 -k privileged-chage"

      # Monitor all execve calls by root (uid 0)
      "-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=4294967295 -k privileged-exec"
      "-a always,exit -F arch=b32 -S execve -F euid=0 -F auid>=1000 -F auid!=4294967295 -k privileged-exec"

      # Monitor setuid/setgid program execution
      "-a always,exit -F arch=b64 -S execve -F sgid>=1 -F egid!=gid -k privileged-sgid"
      "-a always,exit -F arch=b32 -S execve -F sgid>=1 -F egid!=gid -k privileged-sgid"

      # ===================================================================
      # SECTION 4: File access to sensitive paths
      # ===================================================================

      # Sensitive system files
      "-w /etc/sudoers -p wa -k sudoers-change"
      "-w /etc/sudoers.d/ -p wa -k sudoers-change"
      "-w /etc/hosts -p wa -k hosts-change"
      "-w /etc/hostname -p wa -k hostname-change"
      "-w /etc/resolv.conf -p wa -k dns-change"
      "-w /etc/nsswitch.conf -p wa -k nsswitch-change"

      # NixOS configuration (if present on the host)
      "-w /etc/nixos/ -p wa -k nixos-config-change"

      # Service data directories
      "-w /var/lib/ollama/ -p wa -k ollama-data"
      "-w /var/lib/ai-api/ -p wa -k ai-api-data"
      "-w /var/lib/agent-runner/ -p wa -k agent-data"

      # Cryptographic material
      "-w /etc/ssl/ -p wa -k crypto-change"
      "-w /etc/pki/ -p wa -k crypto-change"

      # ===================================================================
      # SECTION 5: Identity file monitoring (NixOS declarative user management)
      # ===================================================================

      # NixOS manages users declaratively -- useradd/usermod/groupadd/groupdel
      # do NOT exist as user-invocable commands. Instead, monitor the identity
      # files that change when nixos-rebuild applies user/group declarations.
      "-w /etc/passwd -p wa -k identity"
      "-w /etc/group -p wa -k identity"
      "-w /etc/shadow -p wa -k identity"
      "-w /etc/gshadow -p wa -k identity"

      # Monitor the NixOS system profile for rebuild events (covers user changes)
      "-w /nix/var/nix/profiles/system -p wa -k nixos-rebuild"
      "-w /run/current-system -p wa -k nixos-generation-switch"

      # ===================================================================
      # SECTION 6: System call monitoring for security-relevant operations
      # ===================================================================

      # File deletion events
      "-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k file-delete"
      "-a always,exit -F arch=b32 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=4294967295 -k file-delete"

      # File permission changes
      "-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm-change"
      "-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm-change"

      # File ownership changes
      "-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k owner-change"
      "-a always,exit -F arch=b32 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k owner-change"

      # Module loading
      "-a always,exit -F arch=b64 -S init_module -S finit_module -S delete_module -k kernel-module"
      "-a always,exit -F arch=b32 -S init_module -S finit_module -S delete_module -k kernel-module"

      # Mount operations
      "-a always,exit -F arch=b64 -S mount -S umount2 -F auid>=1000 -F auid!=4294967295 -k mount-ops"
      "-a always,exit -F arch=b32 -S mount -S umount2 -F auid>=1000 -F auid!=4294967295 -k mount-ops"

      # Time changes
      "-a always,exit -F arch=b64 -S adjtimex -S settimeofday -S clock_settime -k time-change"
      "-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S clock_settime -k time-change"
      "-w /etc/localtime -p wa -k time-change"

      # Network configuration changes
      "-a always,exit -F arch=b64 -S sethostname -S setdomainname -k network-config"
      "-a always,exit -F arch=b32 -S sethostname -S setdomainname -k network-config"

      # ===================================================================
      # SECTION 7: Additional security-relevant syscalls
      # ===================================================================

      # personality() -- container escape vector via execution domain manipulation
      "-a always,exit -F arch=b64 -S personality -F auid>=1000 -F auid!=4294967295 -k personality-change"
      "-a always,exit -F arch=b32 -S personality -F auid>=1000 -F auid!=4294967295 -k personality-change"

      # ptrace -- process debugging/injection, used in many exploit chains
      "-a always,exit -F arch=b64 -S ptrace -F auid>=1000 -F auid!=4294967295 -k process-trace"
      "-a always,exit -F arch=b32 -S ptrace -F auid>=1000 -F auid!=4294967295 -k process-trace"

      # open_by_handle_at -- container escape via file handle (CVE-2015-1397 class)
      "-a always,exit -F arch=b64 -S open_by_handle_at -F auid>=1000 -F auid!=4294967295 -k file-handle-open"
      "-a always,exit -F arch=b32 -S open_by_handle_at -F auid>=1000 -F auid!=4294967295 -k file-handle-open"

      # Failed file access attempts (EACCES and EPERM)
      "-a always,exit -F arch=b64 -S open -S openat -S creat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access-denied"
      "-a always,exit -F arch=b64 -S open -S openat -S creat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access-denied"
      "-a always,exit -F arch=b32 -S open -S openat -S creat -S truncate -S ftruncate -F exit=-EACCES -F auid>=1000 -F auid!=4294967295 -k access-denied"
      "-a always,exit -F arch=b32 -S open -S openat -S creat -S truncate -S ftruncate -F exit=-EPERM -F auid>=1000 -F auid!=4294967295 -k access-denied"

      # ===================================================================
      # SECTION 8: Lock the audit rules (must be last)
      # ===================================================================

      # Make rules immutable -- requires reboot to change
      "-e 2"
    ];
  };

  # Auditd configuration
  environment.etc."audit/auditd.conf".text = ''
    log_file = /var/log/audit/audit.log
    log_format = ENRICHED
    log_group = root
    priority_boost = 4
    freq = 50
    num_logs = 10
    disp_qos = lossy
    dispatcher = /run/current-system/sw/bin/audispd
    name_format = HOSTNAME
    max_log_file = 50
    max_log_file_action = ROTATE
    space_left = 100
    space_left_action = SYSLOG
    admin_space_left = 50
    admin_space_left_action = HALT
    disk_full_action = HALT
    disk_error_action = HALT
    flush = INCREMENTAL_ASYNC
  '';
}
```

### 6.2 Log Storage: Retention and Disk Thresholds (CAT II / CAT III)

```nix
{
  # Journald retention and storage configuration
  services.journald.extraConfig = ''
    # STIG: Minimum 90-day retention for audit records
    MaxRetentionSec=90day

    # Storage thresholds
    SystemMaxUse=4G
    SystemKeepFree=1G
    SystemMaxFileSize=512M

    # Runtime journal limits
    RuntimeMaxUse=512M
    RuntimeKeepFree=256M

    # Compress journal entries
    Compress=yes

    # Forward to syslog for additional log pipeline if needed
    ForwardToSyslog=yes

    # Store persistently (not just in /run)
    Storage=persistent
  '';

  # Ensure /var/log is on a partition with adequate space
  # This is a deployment-time concern; document the requirement
  # Minimum recommended: 10 GB for /var/log, 2 GB for /var/log/audit

  # Time synchronization for accurate timestamps
  services.chrony = {
    enable = true;
    servers = [
      "0.nixos.pool.ntp.org"
      "1.nixos.pool.ntp.org"
      "2.nixos.pool.ntp.org"
      "3.nixos.pool.ntp.org"
    ];
    extraConfig = ''
      # STIG: NTP authentication and drift management
      makestep 1 3
      rtcsync
      driftfile /var/lib/chrony/drift
      logdir /var/log/chrony
    '';
  };

  # Disable systemd-timesyncd since we are using chrony
  services.timesyncd.enable = false;
}
```

### 6.3 Log Protection (CAT II)

```nix
{
  # Restrict audit log permissions
  systemd.tmpfiles.rules = [
    "d /var/log/audit 0700 root root -"
    "d /var/log/chrony 0750 chrony chrony -"
    "d /var/log/sudo-io 0700 root root -"
  ];

  # Agent and service accounts must not have write access to /var/log
  # Enforced via systemd ProtectSystem="strict" on all service units
  # and explicit ReadWritePaths that exclude /var/log

  # Audit log rotation with compression
  services.logrotate = {
    enable = true;
    settings = {
      "/var/log/audit/audit.log" = {
        rotate = 52;  # Keep 52 weeks of rotated logs
        weekly = true;
        compress = true;
        delaycompress = true;
        missingok = true;
        notifempty = true;
        create = "0600 root root";
        postrotate = "systemctl kill -s USR1 auditd.service";
      };
    };
  };

  # Alert on audit subsystem failures
  systemd.services.auditd = {
    unitConfig = {
      OnFailure = "notify-admin@%n.service";
    };
  };

  # Admin notification service template
  systemd.services."notify-admin@" = {
    description = "Send failure notification for %i";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/echo \"ALERT: Service %i failed on $(hostname) at $(date)\" | ${pkgs.mailutils}/bin/mail -s \"Service Failure: %i\" root'";
    };
  };
}
```

### 6.4 Centralized Syslog Forwarding to Remote SIEM (CAT II)

STIG requires centralized logging to a remote SIEM for tamper-resistant log retention and correlation. This configuration forwards syslog over TLS to prevent log manipulation by a compromised host.

```nix
{
  # rsyslog with TLS forwarding to a remote SIEM
  services.rsyslogd = {
    enable = true;
    extraConfig = ''
      # Load TLS module for secure log forwarding
      module(load="imuxsock")
      module(load="imjournal" StateFile="imjournal.state")

      # TLS configuration for remote forwarding
      global(
        DefaultNetstreamDriver="gtls"
        DefaultNetstreamDriverCAFile="/etc/ssl/certs/siem-ca.pem"
        DefaultNetstreamDriverCertFile="/etc/ssl/certs/syslog-client.pem"
        DefaultNetstreamDriverKeyFile="/etc/ssl/private/syslog-client-key.pem"
      )

      # Forward all logs to remote SIEM over TLS (port 6514)
      # Adjust the target IP/hostname to your SIEM server
      action(
        type="omfwd"
        target="siem.internal"
        port="6514"
        protocol="tcp"
        StreamDriver="gtls"
        StreamDriverMode="1"
        StreamDriverAuthMode="x509/name"
        StreamDriverPermittedPeer="siem.internal"
        queue.type="LinkedList"
        queue.fileName="siem-fwd"
        queue.maxDiskSpace="1g"
        queue.saveOnShutdown="on"
        action.resumeRetryCount="-1"
      )

      # Also retain local copies for immediate incident response
      *.* /var/log/messages
      auth,authpriv.* /var/log/auth.log
    '';
  };
}
```

### 6.5 Evidence Generation: Audit and Accountability

| Evidence Artifact | Description | Collection Method |
|---|---|---|
| Auditd rule set | Verify comprehensive rules are loaded | `auditctl -l` |
| Audit log sample | Demonstrate events are being captured | `ausearch -ts recent`, `aureport --summary` |
| Journald configuration | Verify retention and storage settings | `journalctl --header`, `cat /etc/systemd/journald.conf` |
| Log file permissions | Verify restricted access on audit logs | `stat /var/log/audit/`, `ls -la /var/log/audit/` |
| Time sync status | Verify NTP is operational | `chronyc tracking`, `chronyc sources` |
| Log retention proof | Verify 90-day retention | `ls -lt /var/log/audit/`, `journalctl --list-boots` |
| Audit immutability | Verify rules are locked | `auditctl -s` (should show `enabled 2`) |
| Remote syslog | Verify TLS forwarding to SIEM is active | `journalctl -u rsyslogd`, check SIEM for received events |

---

## 7. Finding Area 4: Configuration Management

**Severity**: CAT II (missing baseline control, inadequate integrity checking), CAT III (unnecessary packages, disabled-service gaps).

**NIST 800-53 Cross-Reference**: CM-2, CM-3, CM-5, CM-6, CM-7, CM-7(1), CM-8, CM-10, CM-11.
**HIPAA Cross-Reference**: 164.312(c)(2) -- Mechanism to Authenticate ePHI.
**PCI DSS Cross-Reference**: Requirement 1 -- Install and Maintain Network Security Controls, Requirement 6 -- Develop and Maintain Secure Systems.

### 7.1 NixOS Generation Management as Baseline Control (CAT II)

```nix
{
  # Retain last 10 generations for rollback capability
  boot.loader.systemd-boot.configurationLimit = 10;

  # Pin the flake registry to prevent uncontrolled upstream changes
  nix.settings.flake-registry = "";
  nix.registry.nixpkgs.flake = inputs.nixpkgs;

  # Restrict Nix CLI usage to admin only
  nix.settings.allowed-users = [ "admin" "root" ];
  nix.settings.trusted-users = [ "root" ];

  # Prevent user-level package installation
  # The Nix store is read-only; non-admin users cannot install packages
  nix.settings = {
    # Enforce pure evaluation for reproducibility
    pure-eval = true;

    # Enable flakes and nix-command
    experimental-features = [ "nix-command" "flakes" ];
  };

  # Track rebuild events in the system journal
  systemd.services."nixos-rebuild-notify" = {
    description = "Log NixOS rebuild events";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/echo \"NixOS generation $(readlink /nix/var/nix/profiles/system | sed s/.*-//) activated at $(date)\" | ${pkgs.systemd}/bin/systemd-cat -t nixos-rebuild -p info'";
    };
  };
}
```

### 7.2 AIDE Integrity Checking (CAT II)

```nix
{
  environment.systemPackages = [ pkgs.aide ];

  # AIDE configuration file
  environment.etc."aide.conf".text = ''
    # AIDE configuration for STIG compliance
    database_in=file:/var/lib/aide/aide.db
    database_out=file:/var/lib/aide/aide.db.new
    database_new=file:/var/lib/aide/aide.db.new

    # Hash algorithms -- SHA-512 as required by STIG
    gzip_dbout=yes
    report_url=file:/var/log/aide/aide-report.txt
    report_url=stdout

    # Rule definitions
    NORMAL = sha512+p+u+g+s+m+c+acl+selinux+xattrs
    DIR = p+u+g+acl+selinux+xattrs
    PERMS = p+u+g+acl+selinux+xattrs
    LOG = p+u+g+sha512
    CONTENT = sha512+ftype
    CONTENT_EX = sha512+ftype+p+u+g+acl+selinux+xattrs
    DATAONLY = sha512

    # NixOS-correct paths (traditional /usr/bin etc. are empty on NixOS)
    # See prd.md Appendix A.12 for canonical AIDE paths
    /run/current-system/sw/bin R+sha512
    /run/current-system/sw/sbin R+sha512
    /etc R+sha512
    /boot R+sha512
    /var/lib/ollama/models R+sha256
    /nix/var/nix/profiles/system R+sha512
    # DO NOT monitor /usr/bin, /sbin, /usr/lib — they do not exist on NixOS

    # NixOS-specific: monitor the current system symlink
    /run/current-system CONTENT_EX

    # SSH keys and configuration
    /etc/ssh CONTENT_EX

    # PAM configuration
    /etc/pam.d CONTENT_EX
    /etc/security CONTENT_EX

    # Audit configuration
    /etc/audit CONTENT_EX

    # Service data directories (content changes expected, monitor permissions)
    /var/lib/ollama PERMS
    /var/lib/ai-api PERMS
    /var/lib/agent-runner PERMS

    # Log directories (content changes expected, monitor permissions)
    /var/log/audit PERMS

    # Exclusions -- paths that change frequently by design
    !/var/log/.*
    !/var/lib/aide/.*
    !/proc
    !/sys
    !/dev
    !/run
    !/tmp
    !/nix/store
    !/nix/var
  '';

  # AIDE initialization service (run once, then periodic checks)
  systemd.services.aide-init = {
    description = "Initialize AIDE database";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'if [ ! -f /var/lib/aide/aide.db ]; then ${pkgs.aide}/bin/aide --config /etc/aide.conf --init && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db; fi'";
    };
  };

  # AIDE hourly integrity check service
  systemd.services.aide-check = {
    description = "AIDE filesystem integrity check";
    after = [ "aide-init.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.aide}/bin/aide --config /etc/aide.conf --check || (echo \"AIDE INTEGRITY VIOLATION DETECTED\" | systemd-cat -t aide-alert -p crit && exit 1)'";
      # Run as root to access all monitored paths
      User = "root";
    };
    unitConfig = {
      OnFailure = "aide-alert.service";
    };
  };

  # AIDE hourly timer
  systemd.timers.aide-check = {
    description = "Run AIDE integrity check hourly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;  # Run immediately if a scheduled check was missed
      RandomizedDelaySec = "5m";  # Prevent exact-hour thundering herd
    };
  };

  # AIDE alert service -- triggered on integrity violations
  systemd.services.aide-alert = {
    description = "AIDE integrity violation alert";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.coreutils}/bin/echo \"CRITICAL: AIDE detected unauthorized filesystem changes on $(hostname) at $(date). Review /var/log/aide/aide-report.txt immediately.\" | ${pkgs.mailutils}/bin/mail -s \"AIDE INTEGRITY ALERT - $(hostname)\" root'";
    };
  };

  # AIDE database update service (run after approved changes)
  systemd.services.aide-update = {
    description = "Update AIDE database after approved changes";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.aide}/bin/aide --config /etc/aide.conf --update && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db && echo \"AIDE database updated at $(date)\" | systemd-cat -t aide-update -p info'";
    };
  };

  # Ensure AIDE directories exist with proper permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/aide 0700 root root -"
    "d /var/log/aide 0700 root root -"
  ];
}
```

### 7.3 Minimal Installed Packages (CAT III)

```nix
{
  # Whitelist of approved system packages
  environment.systemPackages = with pkgs; [
    # Core utilities
    coreutils
    findutils
    gnugrep
    gnused
    gawk
    less
    file
    which
    procps
    psmisc
    util-linux

    # Network diagnostics (restricted to admin use). nftables is the
    # project backend per prd.md Appendix A.2; do not add the legacy
    # `iptables` package — it resolves to `iptables-nft` on 24.11 and
    # produces confusing output when admins expect native iptables
    # semantics. Use `nft` directly.
    iproute2
    nftables
    tcpdump  # CAT III: consider removing if not needed for troubleshooting

    # Security and audit tools
    aide
    audit
    libpwquality
    google-authenticator

    # rfkill for wireless/Bluetooth hardware enforcement
    util-linux  # rfkill is included in util-linux

    # Text editors
    vim

    # Shells
    bash

    # System monitoring
    htop
    lsof

    # Nix tooling
    nix

    # TLS and crypto
    openssl
  ];

  # Explicitly disable GUI and unnecessary services
  services.xserver.enable = false;
  services.avahi.enable = false;
  services.printing.enable = false;
  services.pipewire.enable = false;
  services.pulseaudio.enable = false;
  hardware.bluetooth.enable = false;
  networking.wireless.enable = false;

  # Disable NixOS documentation generation to reduce attack surface
  documentation.enable = false;
  documentation.man.enable = true;  # Keep man pages for operational use
  documentation.nixos.enable = false;
}
```

### 7.4 Kernel Module Blacklisting (CAT III)

All kernel module blacklisting is consolidated here in a single definitive list. Do NOT duplicate `boot.blacklistedKernelModules` in other sections -- NixOS list options are merged, but maintaining a single source of truth prevents drift and audit confusion.

```nix
{
  # Canonical module blacklist per prd.md Appendix A.10
  boot.blacklistedKernelModules = [
    # Unnecessary filesystem modules
    "cramfs"
    "freevxfs"
    "jffs2"
    "hfs"
    "hfsplus"
    "squashfs"
    "udf"

    # Unnecessary network protocols
    "dccp"
    "sctp"
    "rds"
    "tipc"

    # Bluetooth (not needed on a server)
    "bluetooth"
    "btusb"

    # Wireless (not needed on a wired server)
    "cfg80211"
    "mac80211"

    # Firewire (attack vector for DMA)
    "firewire-core"
    "firewire-ohci"
    "firewire-sbp2"
    "firewire-net"
    "ohci1394"
    "sbp2"
    "dv1394"
    "raw1394"
    "video1394"

    # Thunderbolt DMA (if not needed; also mitigated by IOMMU in Section 3A.7)
    "thunderbolt"

    # USB mass storage (controlled separately via udev; belt-and-suspenders)
    "usb-storage"
    "uas"

    # Uncommon input devices
    "pcspkr"
    "snd_pcsp"

    # Floppy
    "floppy"
  ];
}
```

### 7.5 rfkill Enforcement for Wireless and Bluetooth (CAT II)

In addition to kernel module blacklisting, rfkill provides a hardware-level enforcement mechanism to ensure wireless and Bluetooth radios are disabled even if modules are somehow loaded.

```nix
{
  # Disable all wireless and Bluetooth radios via rfkill at boot
  systemd.services.rfkill-block-all = {
    description = "Block all wireless and Bluetooth radios via rfkill";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udev-settle.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.util-linux}/bin/rfkill block all";
    };
  };

  # Periodic check to ensure radios remain blocked
  systemd.timers.rfkill-enforce = {
    description = "Periodically enforce rfkill block";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };

  systemd.services.rfkill-enforce = {
    description = "Re-enforce rfkill block on all radios";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.util-linux}/bin/rfkill block all";
    };
  };
}
```

### 7.6 Evidence Generation: Configuration Management

| Evidence Artifact | Description | Collection Method |
|---|---|---|
| Generation history | Full list of NixOS generations with timestamps | `nixos-rebuild list-generations` |
| Flake lock file | Pinned input versions | `cat flake.lock`, `nix flake metadata` |
| Package inventory | Complete list of installed packages | `nix-store --query --requisites /run/current-system` |
| AIDE database | Integrity baseline | `ls -la /var/lib/aide/aide.db` |
| AIDE report | Most recent integrity check output | `cat /var/log/aide/aide-report.txt` |
| Blacklisted modules | Verify kernel module blacklist | `cat /etc/modprobe.d/blacklist.conf` |
| Service inventory | Running services | `systemctl list-units --type=service --state=running` |
| Git history | Configuration change log | `git log --oneline` in flake repository |
| rfkill status | Verify wireless/Bluetooth radios are blocked | `rfkill list all` |

---

## 8. Finding Area 5: System and Communications Protection

**Severity**: CAT I (missing encryption, firewall disabled), CAT II (weak kernel parameters, missing TLS).

**NIST 800-53 Cross-Reference**: SC-4, SC-5, SC-7, SC-8, SC-8(1), SC-12, SC-13, SC-23, SC-28, SC-39.
**HIPAA Cross-Reference**: 164.312(a)(2)(iv) -- Encryption and Decryption, 164.312(e)(1) -- Transmission Security.
**PCI DSS Cross-Reference**: Requirement 1 -- Network Security Controls, Requirement 4 -- Strong Cryptography.

### 8.1 Full-Disk Encryption via LUKS (CAT I)

Full-disk encryption is a boot-time requirement, not configured in the flake itself. This section documents the requirement and verification procedure.

```nix
{
  # LUKS is configured in hardware-configuration.nix during installation
  # Example (system-specific, generated at install time):
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
    preLVM = true;
    allowDiscards = true;  # Required for SSD TRIM; evaluate risk vs. performance

    # STIG: Use strong cipher for LUKS
    # This is set during cryptsetup luksFormat, not in NixOS config
    # Required: aes-xts-plain64, key size 512 (256-bit AES-XTS)
    # Verify with: cryptsetup luksDump /dev/sdX
  };

  # Encrypted swap (if swap is enabled)
  swapDevices = [
    {
      device = "/dev/disk/by-uuid/YYYYYYYY-YYYY-YYYY-YYYY-YYYYYYYYYYYY";
      randomEncryption = {
        enable = true;
        cipher = "aes-xts-plain64";
        keySize = 512;
      };
    }
  ];
}
```

**Verification**: `cryptsetup luksDump /dev/sdX` must show `aes-xts-plain64` cipher with 512-bit key size. This is established at install time and cannot be changed by the flake.

### 8.2 TLS 1.2+ Enforcement via Nginx Reverse Proxy (CAT II)

```nix
{
  services.nginx = {
    enable = true;

    # CAT II: Only TLS 1.2 and 1.3
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;

    # Global SSL settings
    appendHttpConfig = ''
      # STIG: Disable weak protocols
      ssl_protocols TLSv1.2 TLSv1.3;

      # STIG: Strong cipher suites only
      # NOTE: CHACHA20-POLY1305 is included here for non-FIPS deployments where
      # it provides better performance on systems without AES-NI. For FIPS-required
      # deployments, see Section 11.3 which provides a FIPS-only cipher list that
      # excludes CHACHA20-POLY1305 (it is not FIPS-approved).
      ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
      ssl_prefer_server_ciphers on;

      # STIG: HSTS (even on LAN, defense in depth)
      add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

      # Session caching for performance
      ssl_session_cache shared:SSL:10m;
      ssl_session_timeout 10m;
      ssl_session_tickets off;

      # OCSP stapling (if using CA-signed certs)
      ssl_stapling on;
      ssl_stapling_verify on;
    '';

    virtualHosts = {
      # Reverse proxy for Ollama API.
      # Nginx is the one service intentionally exposed on the LAN; bind
      # to the LAN interface address, never 0.0.0.0 on multi-NIC hosts
      # (per prd.md Appendix A.1). For a single-NIC host, the LAN
      # interface address equals 0.0.0.0 plus firewall gating — prefer
      # the explicit address so intent survives a future second NIC.
      "ollama.internal" = {
        listen = [
          { addr = "<LAN_INTERFACE_IP>"; port = 443; ssl = true; }
        ];
        sslCertificate = "/var/lib/nginx/ssl/server.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/server.key";
        locations."/" = {
          proxyPass = "http://127.0.0.1:11434";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_read_timeout 600;
            proxy_connect_timeout 600;
          '';
        };
      };

      # Reverse proxy for Application API — same LAN-interface rule as
      # the Ollama virtualHost above.
      "api.internal" = {
        listen = [
          { addr = "<LAN_INTERFACE_IP>"; port = 8443; ssl = true; }
        ];
        sslCertificate = "/var/lib/nginx/ssl/server.crt";
        sslCertificateKey = "/var/lib/nginx/ssl/server.key";
        locations."/" = {
          proxyPass = "http://127.0.0.1:8000";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };
    };
  };

  # Nginx service hardening
  systemd.services.nginx.serviceConfig = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    ReadWritePaths = [ "/var/lib/nginx" "/var/log/nginx" "/var/cache/nginx" ];
    CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
    AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
  };
}
```

### 8.3 Kernel Hardening via sysctl (CAT I / CAT II)

```nix
{
  # Kernel hardening — values consistent across all framework modules
  boot.kernel.sysctl = {
    # ===================================================================
    # Network hardening (CAT I / CAT II)
    # ===================================================================

    # CAT II: Reject ICMP redirects to prevent MITM
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;

    # CAT II: Do not send ICMP redirects (not a router)
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;

    # CAT II: Reject source-routed packets
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;

    # CAT II: Disable IP forwarding (not a router)
    "net.ipv4.ip_forward" = 0;
    "net.ipv6.conf.all.forwarding" = 0;

    # CAT II: Enable SYN cookies for SYN flood protection
    "net.ipv4.tcp_syncookies" = 1;

    # CAT II: Log martian packets (impossible source addresses)
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.default.log_martians" = 1;

    # CAT II: Ignore ICMP broadcast requests
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;

    # CAT II: Ignore bogus ICMP error responses
    "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

    # CAT II: Enable reverse path filtering
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;

    # CAT II: Disable IPv6 router advertisements (not a router)
    "net.ipv6.conf.all.accept_ra" = 0;
    "net.ipv6.conf.default.accept_ra" = 0;

    # CAT II: Disable TCP timestamps to prevent information leakage
    "net.ipv4.tcp_timestamps" = 0;

    # CAT II: TIME-WAIT assassination protection (RFC 1337)
    "net.ipv4.tcp_rfc1337" = 1;

    # ===================================================================
    # Kernel hardening (CAT I / CAT II)
    # ===================================================================

    # CAT I: Enable ASLR (Address Space Layout Randomization)
    "kernel.randomize_va_space" = 2;

    # CAT II: Restrict dmesg access to root
    "kernel.dmesg_restrict" = 1;

    # CAT II: Restrict kernel pointer exposure
    "kernel.kptr_restrict" = 2;

    # CAT II: Restrict ptrace to parent processes only (Yama LSM)
    "kernel.yama.ptrace_scope" = 2;

    # CAT II: Restrict unprivileged BPF
    "kernel.unprivileged_bpf_disabled" = 1;

    # CAT II: Restrict userfaultfd to privileged users
    "vm.unprivileged_userfaultfd" = 0;

    # CAT II: Restrict performance events
    "kernel.perf_event_paranoid" = 3;

    # CAT II: Disable core dumps for SUID programs
    "fs.suid_dumpable" = 0;

    # CAT II: Disable SysRq key entirely
    "kernel.sysrq" = 0;

    # CAT II: Protect hardlinks and symlinks
    "fs.protected_hardlinks" = 1;
    "fs.protected_symlinks" = 1;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;

    # ===================================================================
    # Memory and process hardening
    # ===================================================================

    # Reduce information leaks
    "kernel.printk" = "3 3 3 3";

    # Restrict loading of TTY line disciplines
    "dev.tty.ldisc_autoload" = 0;

    # JIT compiler hardening
    "net.core.bpf_jit_harden" = 2;

    # CAT II: Prevent core dump exfiltration
    "kernel.core_pattern" = "|/bin/false";

    # CAT II: Auto-reboot on kernel panic after 60 seconds
    "kernel.panic" = 60;

    # CAT II: Treat kernel oops as panic (force reboot on corruption)
    "kernel.panic_on_oops" = 1;

    # CAT II: Disable io_uring (recent exploit vector, not needed for this workload)
    "kernel.io_uring_disabled" = 2;
  };

  # Additional boot parameters for security
  boot.kernelParams = [
    # Disable kernel module loading after boot (aggressive -- evaluate impact)
    # "modules_disabled=1"  # Uncomment if no runtime module loading is needed

    # Disable kexec (prevent kernel replacement at runtime)
    "kexec_load_disabled=1"

    # SLAB hardening
    "slab_nomerge"
    "init_on_alloc=1"
    "init_on_free=1"

    # Page allocation randomization
    "page_alloc.shuffle=1"

    # Disable vsyscall (legacy interface)
    "vsyscall=none"

    # Lockdown kernel in integrity mode (allows NVIDIA driver)
    # "lockdown=integrity"  # May conflict with proprietary NVIDIA driver; test first

    # IOMMU for DMA protection (also configured in Section 3A.7)
    # For Intel systems:
    "intel_iommu=on"
    "iommu=pt"
    # For AMD systems (uncomment and comment out Intel lines):
    # "amd_iommu=on"
    # "iommu=pt"
  ];
}
```

### 8.4 Firewall: LAN-Only with Default Deny (CAT I)

```nix
{
  networking.firewall = {
    enable = true;

    # CAT I: Default deny on all interfaces
    allowedTCPPorts = [];
    allowedUDPPorts = [];

    # Only the LAN-facing interface accepts connections
    interfaces.enp3s0 = {
      allowedTCPPorts = [
        22     # SSH (administration)
        443    # Nginx TLS reverse proxy for Ollama
        8443   # Nginx TLS reverse proxy for Application API
      ];
    };

    # CAT II: Log dropped packets for audit trail
    logReversePathDrops = true;
    logRefusedConnections = true;
    logRefusedPackets = true;

    # CAT II: Reject rather than drop (provides feedback to legitimate LAN clients)
    rejectPackets = true;

    # CAT II: Enable connection tracking
    connectionTrackingModules = [];
    autoLoadConntrackHelpers = false;

    # (extraCommands intentionally unused — see separate nftables table below)
  };

  # Egress control via nftables (NixOS 24.11 default; never mix with
  # iptables-style extraCommands — the two backends conflict).
  networking.nftables.tables.egress-control = {
    family = "inet";
    content = ''
      chain output-lan-only {
        type filter hook output priority 0; policy drop;
        ct state established,related accept
        oif lo accept

        # LAN-only outbound (RFC1918)
        ip daddr 10.0.0.0/8 accept
        ip daddr 172.16.0.0/12 accept
        ip daddr 192.168.0.0/16 accept

        # DNS to LAN DNS server (adjust IP per deployment)
        ip daddr 10.0.0.1 udp dport 53 accept
        ip daddr 10.0.0.1 tcp dport 53 accept

        # NTP to configured time servers
        udp dport 123 accept
      }
    '';
  };

  # Disable IPv6 if not needed on the LAN
  networking.enableIPv6 = false;
}
```

### 8.5 Evidence Generation: System and Communications Protection

| Evidence Artifact | Description | Collection Method |
|---|---|---|
| LUKS verification | Confirm disk encryption is active | `cryptsetup luksDump /dev/sdX`, `lsblk -f` |
| Sysctl values | Verify kernel hardening parameters | `sysctl -a \| grep -E 'randomize_va\|dmesg_restrict\|kptr_restrict\|ptrace_scope\|syncookies\|accept_redirects\|ip_forward\|tcp_timestamps\|tcp_rfc1337\|io_uring_disabled\|panic'` |
| Firewall rules | Verify default deny and port allowlist | `iptables -L -v -n`, `nft list ruleset` |
| TLS configuration | Verify TLS 1.2+ and cipher suites | `openssl s_client -connect localhost:443`, `nginx -T \| grep ssl` |
| Kernel parameters | Verify boot parameters | `cat /proc/cmdline` |
| Module blacklist | Verify blacklisted kernel modules | `lsmod`, `cat /etc/modprobe.d/blacklist.conf` |
| Network interfaces | Verify only LAN interface is active | `ip addr show`, `ip link show` |
| IOMMU status | Verify IOMMU is enabled for DMA protection | `dmesg \| grep -i iommu` |

---

## 9. Finding Area 6: System and Information Integrity

**Severity**: CAT II (missing integrity monitoring, no malware scanning), CAT III (USB controls, update strategy).

**NIST 800-53 Cross-Reference**: SI-2, SI-3, SI-4, SI-5, SI-7, SI-10, SI-16.
**HIPAA Cross-Reference**: 164.308(a)(5)(ii)(B) -- Protection from Malicious Software.
**PCI DSS Cross-Reference**: Requirement 5 -- Protect All Systems Against Malware, Requirement 11 -- Test Security of Systems.

### 9.1 File Integrity via AIDE

Cross-reference: Section 7.2 provides the complete AIDE configuration. This finding area requires that AIDE is operational with hourly checks, SHA-512 hashing, and alerting on detected drift.

### 9.2 ClamAV Malware Scanning (CAT III)

ClamAV provides belt-and-suspenders malware detection. NixOS has a minimal attack surface due to the immutable Nix store, but STIG expectations and defense-in-depth principles warrant scanning of user-writable paths.

```nix
{
  services.clamav = {
    daemon = {
      enable = true;
      settings = {
        # Scan configuration
        MaxFileSize = "100M";
        MaxScanSize = "400M";
        MaxRecursion = 16;
        MaxFiles = 10000;

        # Socket for on-demand scanning
        LocalSocket = "/run/clamav/clamd.ctl";
        LocalSocketMode = "660";

        # Performance tuning
        ConcurrentDatabaseReload = false;

        # Logging
        LogFile = "/var/log/clamav/clamd.log";
        LogFileMaxSize = "50M";
        LogRotate = true;
        LogTime = true;
        LogVerbose = true;

        # Alert on detection
        VirusEvent = "/run/current-system/sw/bin/clamav-alert %v";

        # Exclude Nix store (immutable, extremely large)
        ExcludePath = [
          "^/nix/store"
          "^/proc"
          "^/sys"
          "^/dev"
        ];
      };
    };

    updater = {
      enable = true;
      frequency = 4;  # Check for signature updates 4 times per day
      settings = {
        # Use LAN mirror if available, otherwise official
        DatabaseMirror = [
          "database.clamav.net"
        ];
        # Log updates
        UpdateLogFile = "/var/log/clamav/freshclam.log";
        LogTime = true;
      };
    };
  };

  # Scheduled full scan of user-writable paths
  systemd.services.clamav-scan = {
    description = "ClamAV scheduled malware scan";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.clamav}/bin/clamscan --recursive --infected --log=/var/log/clamav/scan-$(date +%%Y%%m%%d).log /home /var/lib/ollama /var/lib/ai-api /var/lib/agent-runner /tmp 2>&1 || true'";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.clamav-scan = {
    description = "Run ClamAV scan daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # ClamAV alert script
  environment.etc."clamav-alert.sh" = {
    mode = "0755";
    text = ''
      #!/usr/bin/env bash
      VIRUS_NAME="$1"
      echo "MALWARE DETECTED: $VIRUS_NAME on $(hostname) at $(date)" | systemd-cat -t clamav-alert -p crit
      echo "MALWARE DETECTED: $VIRUS_NAME on $(hostname) at $(date)" | mail -s "MALWARE ALERT - $(hostname)" root
    '';
  };

  # Log directory
  systemd.tmpfiles.rules = [
    "d /var/log/clamav 0750 clamav clamav -"
  ];
}
```

### 9.3 Automatic Security Updates via Flake Pinning (CAT II)

NixOS does not use traditional package manager updates. Security updates are managed through flake input updates, rebuild, and rollback.

```nix
{
  # Strategy: automated flake update check with manual approval for rebuild
  # This provides awareness without risking unattended breaking changes

  # Automated check for available updates
  systemd.services.flake-update-check = {
    description = "Check for NixOS security updates";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.nix}/bin/nix flake update --dry-run 2>&1 | systemd-cat -t flake-update -p info'";
      WorkingDirectory = "/etc/nixos";
    };
  };

  systemd.timers.flake-update-check = {
    description = "Check for NixOS updates daily";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  # Automatic security advisory monitoring
  # NixOS Vuln-Tracker integration
  systemd.services.vuln-check = {
    description = "Check for known vulnerabilities in installed packages";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      # NOTE: `pkgs.vulnix or pkgs.nix` is not valid Nix syntax.
      # vulnix must be in the package set. Add to environment.systemPackages.
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.vulnix}/bin/vulnix --system 2>&1 | systemd-cat -t vuln-check -p warning'";
    };
  };

  systemd.timers.vuln-check = {
    description = "Check for vulnerabilities weekly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };

  # Nix garbage collection to remove old generations
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
```

### 9.4 USB and Removable Media Controls (CAT II)

Note: Kernel module blacklisting for `usb-storage` and `uas` is consolidated in Section 7.4. Do NOT duplicate `boot.blacklistedKernelModules` here. This section provides the complementary udev-level controls.

```nix
{
  # udev rules to block USB mass storage devices at the device level
  services.udev.extraRules = ''
    # STIG: Block USB mass storage devices
    # This rule prevents any USB mass storage device from being recognized
    ACTION=="add", SUBSYSTEMS=="usb", ATTR{bInterfaceClass}=="08", ATTR{authorized}="0", TAG+="usb-storage-blocked"

    # Block USB wireless adapters (prevent unauthorized wireless)
    ACTION=="add", SUBSYSTEMS=="usb", ATTR{bInterfaceClass}=="e0", ATTR{authorized}="0", TAG+="usb-wireless-blocked"

    # Block USB Bluetooth adapters
    ACTION=="add", SUBSYSTEMS=="usb", ATTR{bInterfaceClass}=="e0", ATTR{bInterfaceSubClass}=="01", ATTR{authorized}="0", TAG+="usb-bluetooth-blocked"

    # Block USB media transfer protocol (MTP) devices
    ACTION=="add", SUBSYSTEMS=="usb", ATTR{bInterfaceClass}=="06", ATTR{authorized}="0", TAG+="usb-mtp-blocked"

    # Allow USB HID (keyboard, mouse) -- necessary for console access
    # ACTION=="add", SUBSYSTEMS=="usb", ATTR{bInterfaceClass}=="03", ATTR{authorized}="1"

    # Log all USB device connections for audit
    ACTION=="add", SUBSYSTEM=="usb", RUN+="${pkgs.bash}/bin/bash -c 'echo USB_DEVICE_CONNECTED: vendor=%s{idVendor} product=%s{idProduct} serial=%s{serial} | systemd-cat -t udev-usb -p notice'"
    ACTION=="remove", SUBSYSTEM=="usb", RUN+="${pkgs.bash}/bin/bash -c 'echo USB_DEVICE_REMOVED: vendor=%s{idVendor} product=%s{idProduct} | systemd-cat -t udev-usb -p notice'"
  '';

  # Disable automounting
  services.udisks2.enable = false;
  services.gvfs.enable = false;

  # Restrict mount operations to root
  security.wrappers = {};  # Audit and restrict any SUID mount binaries
}
```

### 9.5 Evidence Generation: System and Information Integrity

| Evidence Artifact | Description | Collection Method |
|---|---|---|
| AIDE report | Integrity check results | `cat /var/log/aide/aide-report.txt` |
| ClamAV scan log | Most recent scan results | `cat /var/log/clamav/scan-*.log` |
| ClamAV signature date | Verify signatures are current | `sigtool --info /var/lib/clamav/daily.cld` |
| USB device log | History of USB connections | `journalctl -t udev-usb` |
| udev rules | Verify USB mass storage blocking | `udevadm info --export-db \| grep usb-storage-blocked` |
| Flake update log | Evidence of update monitoring | `journalctl -t flake-update` |
| Vulnerability scan | Known CVE check results | `journalctl -t vuln-check` |
| Kernel module state | Verify blacklisted modules are not loaded | `lsmod \| grep -E 'usb.storage\|bluetooth\|firewire'` |

---

## 10. Finding Area 7: Login Notification

**Severity**: CAT III.

**NIST 800-53 Cross-Reference**: AC-8 -- System Use Notification.
**HIPAA Cross-Reference**: 164.310(b) -- Workstation Use (supporting).
**PCI DSS Cross-Reference**: Requirement 12.3 -- Security Policies and Operational Procedures.

### 10.1 SSH Login Banner (CAT III)

The STIG requires a system use notification banner before granting access. The following uses a generic "authorized use only" banner appropriate for private infrastructure. Organizations operating under DoD requirements should substitute the Standard Mandatory DoD Notice and Consent Banner.

```nix
{
  # SSH pre-authentication banner
  services.openssh.banner = ''
    ============================================================================
    NOTICE: AUTHORIZED USE ONLY

    This system is for authorized users only. All activity on this system is
    subject to monitoring, recording, and audit. By accessing this system, you
    consent to such monitoring and acknowledge that:

    - Unauthorized access or use is prohibited and may result in disciplinary
      action, civil liability, and/or criminal prosecution.
    - All access, actions, and data are logged and may be reviewed at any time.
    - There is no expectation of privacy when using this system.
    - Evidence of unauthorized use may be provided to law enforcement.

    If you are not an authorized user, disconnect now.
    ============================================================================
  '';

  # Console login banner (/etc/issue)
  environment.etc."issue".text = ''
    ============================================================================
    NOTICE: AUTHORIZED USE ONLY

    This system is for authorized users only. All activity is monitored and
    logged. Unauthorized access is prohibited. Disconnect immediately if you
    are not authorized.
    ============================================================================
  '';

  # Post-login MOTD with system status
  environment.etc."motd".text = ''
    ============================================================================
    System access is logged. All privileged operations require justification.
    Report security incidents to the system administrator immediately.
    ============================================================================
  '';
}
```

### 10.2 Evidence Generation: Login Notification

| Evidence Artifact | Description | Collection Method |
|---|---|---|
| SSH banner text | Verify banner is displayed before auth | `ssh -v admin@server 2>&1 \| head -30` |
| Console banner | Verify /etc/issue content | `cat /etc/issue` |
| MOTD | Verify post-login message | `cat /etc/motd` |
| SSH config verification | Verify banner path is set | `sshd -T \| grep banner` |

---

## 11. Finding Area 8: FIPS Considerations

**Severity**: CAT I (for systems required to operate in FIPS mode), CAT II (for systems that should prefer FIPS-compatible algorithms).

**NIST 800-53 Cross-Reference**: SC-12 -- Cryptographic Key Establishment and Management, SC-13 -- Cryptographic Protection, IA-7 -- Cryptographic Module Authentication.
**HIPAA Cross-Reference**: 164.312(a)(2)(iv) -- Encryption and Decryption, 164.312(e)(2)(ii) -- Encryption.
**PCI DSS Cross-Reference**: Requirement 4.2.1 -- Strong Cryptography.

### 11.1 SSH FIPS-Compatible Configuration (CAT II)

```nix
{
  services.openssh.settings = {
    # FIPS 140-2/140-3 compatible cipher configuration
    # Only AES-based ciphers with GCM or CTR modes
    Ciphers = [
      "aes256-gcm@openssh.com"
      "aes128-gcm@openssh.com"
      "aes256-ctr"
      "aes192-ctr"
      "aes128-ctr"
    ];

    # FIPS-compatible MACs (HMAC-SHA2 family)
    Macs = [
      "hmac-sha2-512-etm@openssh.com"
      "hmac-sha2-256-etm@openssh.com"
      "hmac-sha2-512"
      "hmac-sha2-256"
    ];

    # FIPS-compatible key exchange algorithms
    KexAlgorithms = [
      "ecdh-sha2-nistp521"
      "ecdh-sha2-nistp384"
      "ecdh-sha2-nistp256"
      "diffie-hellman-group16-sha512"
      "diffie-hellman-group18-sha512"
      "diffie-hellman-group14-sha256"
    ];

    # Host key algorithms -- FIPS-compatible
    HostKeyAlgorithms = [
      "ecdsa-sha2-nistp521"
      "ecdsa-sha2-nistp384"
      "ecdsa-sha2-nistp256"
      "rsa-sha2-512"
      "rsa-sha2-256"
    ];

    # Public key accepted algorithms
    PubkeyAcceptedAlgorithms = [
      "ecdsa-sha2-nistp521"
      "ecdsa-sha2-nistp384"
      "ecdsa-sha2-nistp256"
      "rsa-sha2-512"
      "rsa-sha2-256"
      "ssh-ed25519"  # Not FIPS-approved but widely used; remove for strict FIPS
    ];
  };
}
```

**Note on Ed25519**: Ed25519 is not FIPS-approved as of FIPS 140-3. For strict FIPS compliance, remove `ssh-ed25519` from `PubkeyAcceptedAlgorithms` and use ECDSA (NIST P-256/P-384/P-521) or RSA keys only. For non-DoD deployments, Ed25519 provides equivalent or better security and is widely recommended. The configuration above includes it with a comment for easy removal.

### 11.2 OpenSSL FIPS Provider (CAT II)

**IMPORTANT**: NixOS does NOT ship a FIPS-validated OpenSSL module. The standard NixOS OpenSSL package has not undergone FIPS 140-3 certification. The configuration below selects FIPS-compatible algorithms but does NOT provide FIPS validation. Setting `fips=yes` in `default_properties` without a FIPS provider loaded will cause OpenSSL operations to fail. The FIPS provider configuration is commented out and provided for future use when a FIPS-validated OpenSSL module becomes available for NixOS.

```nix
{
  # OpenSSL configuration for FIPS-compatible algorithm selection
  # NOTE: The FIPS provider is NOT enabled by default because NixOS does not
  # ship a FIPS-validated OpenSSL module. Enabling fips=yes in default_properties
  # without a FIPS provider will break OpenSSL. This configuration restricts
  # algorithm selection to FIPS-compatible choices as a best-effort measure.
  environment.etc."ssl/openssl.cnf".text = ''
    # OpenSSL configuration for FIPS-compatible algorithm selection
    openssl_conf = openssl_init

    [openssl_init]
    providers = provider_sect
    alg_section = algorithm_sect

    [provider_sect]
    default = default_sect
    # FUTURE USE: Uncomment below when a FIPS-validated provider module is
    # available for NixOS. Without a validated module, enabling the FIPS
    # provider will cause OpenSSL to fail.
    # fips = fips_sect

    [default_sect]
    activate = 1

    # [fips_sect]
    # activate = 1
    # module = /path/to/fips.so

    [algorithm_sect]
    # NOTE: Do NOT set default_properties = fips=yes unless the FIPS provider
    # above is activated with a validated module. Setting fips=yes without a
    # loaded FIPS provider will cause all OpenSSL operations to fail.
    # default_properties = fips=yes

    # Restrict to FIPS-compatible cipher suites
    [system_default_sect]
    MinProtocol = TLSv1.2
    CipherString = DEFAULT:!RC4:!DES:!3DES:!MD5:!PSK:!SRP:!DSA:!SEED:!IDEA:!CAMELLIA
    Ciphersuites = TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256
  '';

  # Environment variable to point applications to the FIPS-aware config
  environment.variables = {
    OPENSSL_CONF = "/etc/ssl/openssl.cnf";
  };
}
```

### 11.3 TLS Cipher Suite Restrictions (CAT II)

Two cipher configurations are provided: one for FIPS-required deployments and one for general hardened deployments. The general configuration (Section 8.2) includes CHACHA20-POLY1305 for performance on non-AES-NI hardware. The FIPS configuration below excludes it.

```nix
{
  # Nginx TLS cipher restrictions for FIPS alignment
  # This extends Section 8.2 with FIPS-specific cipher selection
  #
  # NOTE on CHACHA20-POLY1305: This cipher is NOT FIPS-approved. It is included
  # in the general TLS configuration (Section 8.2) for non-FIPS deployments where
  # it provides better performance on systems without AES-NI hardware acceleration.
  # For FIPS-required deployments, use the configuration below which excludes it.

  # NOTE: This appendHttpConfig block conflicts with the one in Section 8.2.
  # In the implementation flake, consolidate both into a single definition
  # or use lib.mkAfter to merge them. Duplicate definitions cause eval errors.
  services.nginx.appendHttpConfig = ''
    # FIPS-compatible TLS cipher suites only
    # CHACHA20-POLY1305 is intentionally excluded (not FIPS-approved)
    ssl_protocols TLSv1.2 TLSv1.3;

    # TLS 1.2 ciphers (FIPS-approved only)
    ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers on;

    # TLS 1.3 cipher suites (FIPS subset)
    # TLS 1.3 ciphersuites are configured differently -- only AES-GCM
    # Note: Nginx TLS 1.3 cipher configuration depends on the OpenSSL version
    # OpenSSL 1.1.1+ supports: TLS_AES_256_GCM_SHA384, TLS_AES_128_GCM_SHA256
    # TLS_CHACHA20_POLY1305_SHA256 is intentionally omitted for FIPS compliance

    # ECDH curve selection -- FIPS-approved NIST curves only
    ssl_ecdh_curve secp521r1:secp384r1:secp256r1;

    # DH parameter size -- minimum 2048 bits for FIPS
    ssl_dhparam /var/lib/nginx/ssl/dhparam.pem;
  '';

  # Generate strong DH parameters (run once during setup)
  systemd.services.nginx-dhparam = {
    description = "Generate DH parameters for Nginx";
    before = [ "nginx.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'if [ ! -f /var/lib/nginx/ssl/dhparam.pem ]; then ${pkgs.openssl}/bin/openssl dhparam -out /var/lib/nginx/ssl/dhparam.pem 4096; fi'";
      RemainAfterExit = true;
    };
  };
}
```

### 11.4 Evidence Generation: FIPS Considerations

| Evidence Artifact | Description | Collection Method |
|---|---|---|
| SSH cipher list | Verify FIPS-compatible ciphers | `sshd -T \| grep -E 'ciphers\|macs\|kexalgorithms'` |
| TLS cipher scan | Verify server cipher suites | `openssl s_client -connect localhost:443 -cipher 'ALL' 2>&1`, `nmap --script ssl-enum-ciphers -p 443 localhost` |
| OpenSSL configuration | Verify FIPS-aware config | `openssl version -a`, `cat /etc/ssl/openssl.cnf` |
| DH parameter strength | Verify DH parameter size | `openssl dhparam -inform PEM -in /var/lib/nginx/ssl/dhparam.pem -text \| head -1` |
| Certificate algorithms | Verify FIPS-compatible key types | `openssl x509 -in /var/lib/nginx/ssl/server.crt -text \| grep 'Public Key Algorithm'` |
| Active cipher negotiation | Verify actual cipher in use | `openssl s_client -connect localhost:443 </dev/null 2>&1 \| grep 'Cipher is'` |

---

## 12. Cross-Framework Reference Matrix

This matrix maps each STIG finding area to controls in other compliance frameworks covered by companion PRD modules.

| STIG Finding Area | NIST 800-53 Controls | HIPAA Safeguards | PCI DSS Requirements | HITRUST CSF |
|---|---|---|---|---|
| Boot Security | SC-39, SI-7, AC-3, AC-6 | 164.310(a)(1) | 9.2, 9.3 | 08.b, 08.j |
| Identification and Authentication | IA-2, IA-2(1), IA-4, IA-5, IA-5(1), IA-8, AC-7 | 164.312(d), 164.308(a)(5)(ii)(D) | 8.2, 8.3, 8.4, 8.5, 8.6 | 01.d, 01.q, 09.j |
| Access Control | AC-2, AC-3, AC-5, AC-6, AC-6(1), AC-6(9), AC-17 | 164.312(a)(1), 164.312(a)(2)(i) | 7.1, 7.2, 7.3, 8.6 | 01.a, 01.b, 01.c, 01.v |
| Audit and Accountability | AU-2, AU-3, AU-4, AU-5, AU-8, AU-9, AU-11, AU-12 | 164.312(b), 164.308(a)(1)(ii)(D) | 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7 | 09.aa, 09.ab, 09.ad |
| Configuration Management | CM-2, CM-3, CM-5, CM-6, CM-7, CM-8, CM-11 | 164.312(c)(2), 164.308(a)(8) | 1.1, 1.2, 2.1, 2.2, 6.1, 6.2 | 10.h, 10.k |
| System and Communications Protection | SC-5, SC-7, SC-8, SC-12, SC-13, SC-28, SC-39 | 164.312(a)(2)(iv), 164.312(e)(1), 164.312(e)(2)(ii) | 1.3, 1.4, 4.1, 4.2 | 09.m, 09.n, 06.d |
| System and Information Integrity | SI-2, SI-3, SI-4, SI-7 | 164.308(a)(5)(ii)(B), 164.312(c)(1) | 5.1, 5.2, 5.3, 11.5 | 09.j, 10.a, 10.m |
| Login Notification | AC-8 | 164.310(b) (supporting) | 12.3 | 01.f |
| FIPS Considerations | SC-12, SC-13, IA-7 | 164.312(a)(2)(iv), 164.312(e)(2)(ii) | 4.2.1 | 06.d, 10.f |

---

## 13. Consolidated Evidence Checklist for Auditors

The following is the complete set of evidence artifacts an auditor needs to verify STIG compliance. Each item references the finding area and specific section where the requirement and configuration are documented.

### 13.1 Pre-Assessment Collection Script

```bash
#!/usr/bin/env bash
# STIG Evidence Collection Script
# Run as root on the target NixOS system

EVIDENCE_DIR="/var/lib/stig-evidence/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$EVIDENCE_DIR"

echo "=== Collecting STIG evidence to $EVIDENCE_DIR ==="

# NixOS system identification
nixos-version > "$EVIDENCE_DIR/nixos-version.txt" 2>&1
nix-info -m > "$EVIDENCE_DIR/nix-info.txt" 2>&1
readlink -f /run/current-system > "$EVIDENCE_DIR/current-system-path.txt" 2>&1

# Flake lock hash (if flake-based)
if [ -f /etc/nixos/flake.lock ]; then
  sha256sum /etc/nixos/flake.lock > "$EVIDENCE_DIR/flake-lock-hash.txt" 2>&1
  cat /etc/nixos/flake.lock > "$EVIDENCE_DIR/flake-lock.json" 2>&1
fi

# Boot Security
mokutil --sb-state > "$EVIDENCE_DIR/secure-boot-status.txt" 2>&1
bootctl status > "$EVIDENCE_DIR/bootctl-status.txt" 2>&1
mount | grep -E '/tmp|/dev/shm|/var/tmp' > "$EVIDENCE_DIR/mount-options.txt" 2>&1
systemctl status ctrl-alt-del.target > "$EVIDENCE_DIR/ctrl-alt-del.txt" 2>&1
systemctl cat emergency.service > "$EVIDENCE_DIR/emergency-service.txt" 2>&1
systemctl cat rescue.service > "$EVIDENCE_DIR/rescue-service.txt" 2>&1
ulimit -c > "$EVIDENCE_DIR/ulimit-core.txt" 2>&1
cat /proc/sys/kernel/core_pattern > "$EVIDENCE_DIR/core-pattern.txt" 2>&1
dmesg | grep -i iommu > "$EVIDENCE_DIR/iommu-status.txt" 2>&1

# Identification and Authentication
sshd -T > "$EVIDENCE_DIR/sshd-config.txt" 2>&1
cat /etc/pam.d/* > "$EVIDENCE_DIR/pam-configs.txt" 2>&1
cat /etc/security/faillock.conf > "$EVIDENCE_DIR/faillock-conf.txt" 2>&1
cat /etc/security/pwquality.conf > "$EVIDENCE_DIR/pwquality-conf.txt" 2>&1
faillock > "$EVIDENCE_DIR/faillock-status.txt" 2>&1
cat /etc/passwd > "$EVIDENCE_DIR/passwd.txt" 2>&1
cat /etc/group > "$EVIDENCE_DIR/group.txt" 2>&1
echo "$TMOUT" > "$EVIDENCE_DIR/tmout.txt" 2>&1

# Access Control
cat /etc/sudoers > "$EVIDENCE_DIR/sudoers.txt" 2>&1
cat /etc/sudoers.d/* > "$EVIDENCE_DIR/sudoers-d.txt" 2>&1
find / -perm /6000 -type f > "$EVIDENCE_DIR/suid-sgid-binaries.txt" 2>&1
umask > "$EVIDENCE_DIR/umask.txt" 2>&1
stat /home/admin > "$EVIDENCE_DIR/home-perms.txt" 2>&1

# Audit and Accountability
auditctl -l > "$EVIDENCE_DIR/audit-rules.txt" 2>&1
auditctl -s > "$EVIDENCE_DIR/audit-status.txt" 2>&1
aureport --summary > "$EVIDENCE_DIR/audit-summary.txt" 2>&1
cat /etc/systemd/journald.conf > "$EVIDENCE_DIR/journald-conf.txt" 2>&1
chronyc tracking > "$EVIDENCE_DIR/chrony-tracking.txt" 2>&1
stat /var/log/audit/ > "$EVIDENCE_DIR/audit-log-perms.txt" 2>&1

# Configuration Management
nixos-rebuild list-generations > "$EVIDENCE_DIR/generations.txt" 2>&1
nix-store --query --requisites /run/current-system > "$EVIDENCE_DIR/package-inventory.txt" 2>&1
ls -la /var/lib/aide/ > "$EVIDENCE_DIR/aide-db.txt" 2>&1
cat /var/log/aide/aide-report.txt > "$EVIDENCE_DIR/aide-report.txt" 2>&1
lsmod > "$EVIDENCE_DIR/loaded-modules.txt" 2>&1
systemctl list-units --type=service --state=running > "$EVIDENCE_DIR/running-services.txt" 2>&1
rfkill list all > "$EVIDENCE_DIR/rfkill-status.txt" 2>&1

# System and Communications Protection
sysctl -a > "$EVIDENCE_DIR/sysctl-all.txt" 2>&1
iptables -L -v -n > "$EVIDENCE_DIR/iptables.txt" 2>&1
cat /proc/cmdline > "$EVIDENCE_DIR/kernel-cmdline.txt" 2>&1
lsblk -f > "$EVIDENCE_DIR/block-devices.txt" 2>&1
ip addr show > "$EVIDENCE_DIR/network-interfaces.txt" 2>&1

# System and Information Integrity
journalctl -t udev-usb --no-pager > "$EVIDENCE_DIR/usb-device-log.txt" 2>&1
journalctl -t flake-update --no-pager > "$EVIDENCE_DIR/flake-update-log.txt" 2>&1

# Login Notification
cat /etc/issue > "$EVIDENCE_DIR/issue.txt" 2>&1
cat /etc/motd > "$EVIDENCE_DIR/motd.txt" 2>&1

# FIPS
openssl version -a > "$EVIDENCE_DIR/openssl-version.txt" 2>&1
cat /etc/ssl/openssl.cnf > "$EVIDENCE_DIR/openssl-conf.txt" 2>&1

# Remote syslog
journalctl -u rsyslogd --no-pager -n 50 > "$EVIDENCE_DIR/rsyslog-status.txt" 2>&1

echo "=== Evidence collection complete: $EVIDENCE_DIR ==="

# Generate hash manifest of all collected evidence for integrity verification
cd "$EVIDENCE_DIR"
sha256sum *.txt *.json 2>/dev/null > "$EVIDENCE_DIR/evidence-manifest-sha256.txt"
echo "Evidence hash manifest: $EVIDENCE_DIR/evidence-manifest-sha256.txt"

tar czf "$EVIDENCE_DIR.tar.gz" -C "$(dirname $EVIDENCE_DIR)" "$(basename $EVIDENCE_DIR)"
echo "Archive: $EVIDENCE_DIR.tar.gz"

# Hash the archive itself for chain-of-custody
sha256sum "$EVIDENCE_DIR.tar.gz" > "$EVIDENCE_DIR.tar.gz.sha256"
echo "Archive hash: $EVIDENCE_DIR.tar.gz.sha256"
```

### 13.2 Evidence Summary Table

| # | Artifact | Finding Area | Section | CAT |
|---|---|---|---|---|
| 1 | NixOS version and system info | System Identification | 13.1 | -- |
| 2 | Flake lock hash | System Identification | 13.1 | -- |
| 3 | Secure Boot status | Boot Security | 3A.1 | I |
| 4 | Bootloader editor/password config | Boot Security | 3A.2 | I |
| 5 | Mount options (/tmp, /dev/shm, /var/tmp) | Boot Security | 3A.3 | II |
| 6 | Ctrl-Alt-Del status | Boot Security | 3A.4 | II |
| 7 | Emergency/rescue mode auth | Boot Security | 3A.5 | I |
| 8 | Core dump configuration | Boot Security | 3A.6 | II |
| 9 | IOMMU/DMA protection status | Boot Security | 3A.7 | II |
| 10 | SSH daemon configuration (`sshd -T`) | Identification and Authentication | 4.1, 4.3, 4.4 | I, II |
| 11 | PAM configuration files | Identification and Authentication | 4.2 | II |
| 12 | Faillock configuration and status | Identification and Authentication | 4.2 | II |
| 13 | Password quality configuration | Identification and Authentication | 4.2 | II |
| 14 | User account listing (`/etc/passwd`) | Identification and Authentication | 4.5 | II |
| 15 | MFA enrollment verification | Identification and Authentication | 4.3 | I |
| 16 | Sudo configuration | Access Control | 5.1 | I |
| 17 | Sudo I/O logs | Access Control | 5.1 | II |
| 18 | SUID/SGID binary audit | Access Control | 5.2 | II |
| 19 | Systemd unit sandboxing verification | Access Control | 5.3 | II |
| 20 | Auditd rules (`auditctl -l`) | Audit and Accountability | 6.1 | II |
| 21 | Audit log samples | Audit and Accountability | 6.1 | II |
| 22 | Journald retention configuration | Audit and Accountability | 6.2 | III |
| 23 | Time synchronization status | Audit and Accountability | 6.2 | II |
| 24 | Audit log permissions | Audit and Accountability | 6.3 | II |
| 25 | Remote syslog forwarding status | Audit and Accountability | 6.4 | II |
| 26 | NixOS generation history | Configuration Management | 7.1 | II |
| 27 | Package inventory | Configuration Management | 7.3 | III |
| 28 | AIDE database and reports | Configuration Management | 7.2 | II |
| 29 | Kernel module blacklist | Configuration Management | 7.4 | III |
| 30 | rfkill status | Configuration Management | 7.5 | II |
| 31 | Sysctl parameters | System and Communications Protection | 8.3 | I, II |
| 32 | Firewall rules | System and Communications Protection | 8.4 | I |
| 33 | LUKS encryption verification | System and Communications Protection | 8.1 | I |
| 34 | TLS configuration | System and Communications Protection | 8.2 | II |
| 35 | AIDE integrity report | System and Information Integrity | 9.1 | II |
| 36 | ClamAV scan logs | System and Information Integrity | 9.2 | III |
| 37 | USB device connection log | System and Information Integrity | 9.4 | II |
| 38 | SSH/console login banners | Login Notification | 10.1 | III |
| 39 | SSH cipher/MAC/KEX configuration | FIPS Considerations | 11.1 | II |
| 40 | OpenSSL configuration | FIPS Considerations | 11.2 | II |
| 41 | TLS cipher verification | FIPS Considerations | 11.3 | II |
| 42 | Evidence hash manifest | Chain of Custody | 13.1 | -- |

---

## 14. Known Gaps and Mitigations

### 14.1 Gaps Requiring Organizational Process

| Gap | Finding Area | Mitigation |
|---|---|---|
| Account review cadence | Identification and Authentication | Organizational policy defining quarterly account review with sign-off documentation. NixOS config provides the account inventory; the review itself is a human process. |
| Separation of duties matrix | Access Control | Documented role matrix defining who can rebuild, who reviews agent outputs, who manages secrets. NixOS enforces the technical boundary; the organizational document defines the policy. |
| Log review schedule | Audit and Accountability | Organizational policy defining weekly log review cadence. The host provides `journalctl` and `aureport` as tooling; the review is a human process. |
| Incident response plan | All | Required by STIG but entirely organizational. The NixOS config supports incident response through rollback (`nixos-rebuild switch --rollback`), audit logs, and AIDE reports. |
| Physical security | All | STIG includes physical security findings that cannot be addressed through NixOS configuration. Physical access to the server console, BIOS/UEFI password, and server room access controls are organizational concerns. |
| FIPS validation | FIPS Considerations | NixOS does not ship FIPS-validated cryptographic modules. For strict FIPS compliance, a FIPS-validated OpenSSL module or alternative implementation is required. The configuration above selects FIPS-compatible algorithms but does not provide FIPS validation. |

### 14.2 Gaps Due to NixOS Platform Specifics

| Gap | Finding Area | Mitigation |
|---|---|---|
| SELinux/AppArmor | Access Control | NixOS has limited SELinux support. Systemd sandboxing (`ProtectSystem`, `NoNewPrivileges`, `SystemCallFilter`) provides equivalent process isolation. Document this compensating control. |
| FIPS-validated OpenSSL | FIPS Considerations | Standard NixOS OpenSSL is not FIPS-validated. Algorithm selection is FIPS-compatible, but the module itself lacks FIPS 140-3 certification. Document as a known deviation with compensating algorithm controls. |
| GPU memory isolation | Access Control | NVIDIA GPU VRAM is not directly manageable via NixOS configuration. Systemd sandboxing restricts which processes can access GPU devices. Residual data in VRAM between inference requests is a known gap. |
| Nix store immutability vs. traditional FIM | Configuration Management | The Nix store is content-addressed and immutable by design, which provides stronger integrity guarantees than traditional FIM for most system paths. AIDE is still deployed for `/etc`, `/home`, and other mutable paths. Document the Nix store's integrity model as a compensating control. |
| Declarative user management vs. traditional audit | Audit and Accountability | NixOS manages users declaratively -- commands like `useradd`/`usermod` are not used interactively. Audit rules monitor the identity files (`/etc/passwd`, `/etc/group`, `/etc/shadow`, `/etc/gshadow`) and the NixOS system profile for changes, rather than monitoring traditional user management binaries that do not exist on NixOS. |

---

## 15. Flake Module Mapping

Each STIG finding area maps to one or more flake modules. This table shows the primary and supporting module responsibilities.

| Finding Area | Primary Module | Supporting Modules |
|---|---|---|
| Boot Security | `stig-baseline` | `hardware-configuration` |
| Identification and Authentication | `stig-baseline` | `lan-only-network` |
| Access Control | `stig-baseline` | `agent-sandbox`, `ai-services`, `gpu-node` |
| Audit and Accountability | `audit-and-aide` | `stig-baseline`, `agent-sandbox`, `ai-services` |
| Configuration Management | `stig-baseline`, `audit-and-aide` | All modules (each must not override baseline settings) |
| System and Communications Protection | `stig-baseline`, `lan-only-network` | `ai-services`, `gpu-node` |
| System and Information Integrity | `audit-and-aide` | `stig-baseline` |
| Login Notification | `stig-baseline` | -- |
| FIPS Considerations | `stig-baseline` | `ai-services`, `lan-only-network` |
