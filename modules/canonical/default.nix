{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  # canonical — single source of truth for every configuration value whose
  # resolution is driven by cross-framework compliance requirements.
  #
  # Each option maps to a numbered subsection of docs/prd/prd.md Appendix A.
  # Downstream modules (stig-baseline, lan-only-network, ai-services, etc.)
  # read from `config.canonical.*` rather than redeclaring values inline.
  # Framework-specific PRD snippets are illustrative only — this module is
  # authoritative. Overrides at the host level must use lib.mkForce so the
  # intent is loud.
  #
  # See todos/01-architecture-and-cross-cutting.md ARCH-02 for the driving
  # rationale and MASTER-REVIEW.md "Systemic Issue #1" for the duplication
  # that justified centralisation.

  options.canonical = {

    # A.1 Service Binding
    serviceBinding = mkOption {
      description = "Network binding policy for every locally-listening service. No AI service binds to 0.0.0.0 — LAN exposure happens only via the Nginx TLS reverse proxy.";
      type = types.submodule {
        options = {
          ollamaHost = mkOption {
            type = types.str;
            description = "Literal OLLAMA_HOST value. 127.0.0.1-only; LAN access goes through Nginx.";
          };
          ollamaOrigins = mkOption {
            type = types.str;
            description = "OLLAMA_ORIGINS allowlist. Restricts cross-origin requests.";
          };
          sshListen = mkOption {
            type = types.str;
            description = "Symbolic target for services.openssh.listenAddresses. 'lan' means the host's LAN interface only; never 0.0.0.0. Real IPs resolved by the host-level module.";
          };
          appApiHost = mkOption {
            type = types.str;
            description = "Listen address for the application API on port 8000. Bound to loopback; exposed via Nginx TLS.";
          };
        };
      };
      default = {
        ollamaHost = "127.0.0.1:11434";
        ollamaOrigins = "http://127.0.0.1:*";
        sshListen = "lan";
        appApiHost = "127.0.0.1:8000";
      };
    };

    # A.2 Firewall Technology
    firewall = mkOption {
      description = "Firewall backend + default policy. nftables exclusively; never networking.firewall.extraCommands with iptables syntax.";
      type = types.submodule {
        options = {
          backend = mkOption {
            type = types.enum [ "nftables" ];
            description = "Firewall backend. Only nftables is permitted.";
          };
          defaultInbound = mkOption {
            type = types.enum [ "deny" ];
            description = "Default inbound policy. Always deny; explicit allowlist per interface.";
          };
          egressFilteringMode = mkOption {
            type = types.enum [ "per-uid-nftables" ];
            description = "Egress filtering mechanism. Per-UID via nftables meta skuid, not iptables --uid-owner.";
          };
        };
      };
      default = {
        backend = "nftables";
        defaultInbound = "deny";
        egressFilteringMode = "per-uid-nftables";
      };
    };

    # A.3 systemd Hardening
    systemdHardening = mkOption {
      description = "systemd unit hardening directives applied uniformly. GPU-facing services omit MemoryDenyWriteExecute because CUDA requires W+X for JIT.";
      type = types.submodule {
        options = {
          memoryDenyWriteExecuteServices = mkOption {
            type = types.listOf types.str;
            description = "Services that MUST set MemoryDenyWriteExecute=true.";
          };
          memoryDenyWriteExecuteExempt = mkOption {
            type = types.listOf types.str;
            description = "Services that MUST NOT set MemoryDenyWriteExecute. CUDA JIT requires W+X memory.";
          };
          protectSystem = mkOption {
            type = types.enum [ "strict" ];
            description = "ProtectSystem mode for all services. strict, never full.";
          };
          commonDirectives = mkOption {
            type = types.attrsOf types.bool;
            description = "Directives applied to every service unit.";
          };
        };
      };
      default = {
        memoryDenyWriteExecuteServices = [ "agent-runner" "ai-api" ];
        memoryDenyWriteExecuteExempt = [ "ollama" ];
        protectSystem = "strict";
        commonDirectives = {
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
        };
      };
    };

    # A.4 SSH Cryptographic Configuration
    ssh = mkOption {
      description = "services.openssh.settings values. FIPS-compatible cipher set; keyboard-interactive enabled to carry TOTP MFA; deprecated directives forbidden.";
      type = types.submodule {
        options = {
          passwordAuthentication = mkOption { type = types.bool; };
          kbdInteractiveAuthentication = mkOption { type = types.bool; };
          authenticationMethods = mkOption { type = types.str; };
          permitRootLogin = mkOption { type = types.enum [ "no" "yes" "prohibit-password" ]; };
          x11Forwarding = mkOption { type = types.bool; };
          allowUsers = mkOption { type = types.listOf types.str; };
          maxSessions = mkOption { type = types.ints.positive; };
          maxStartups = mkOption { type = types.str; };
          ciphers = mkOption { type = types.listOf types.str; };
          macs = mkOption { type = types.listOf types.str; };
          kexAlgorithms = mkOption { type = types.listOf types.str; };
          clientAliveInterval = mkOption { type = types.ints.positive; };
          clientAliveCountMax = mkOption { type = types.ints.unsigned; };
        };
      };
      default = {
        passwordAuthentication = false;
        kbdInteractiveAuthentication = true;
        authenticationMethods = "publickey,keyboard-interactive";
        permitRootLogin = "no";
        x11Forwarding = false;
        allowUsers = [ "admin" ];
        maxSessions = 3;
        maxStartups = "10:30:60";
        ciphers = [
          "aes256-gcm@openssh.com"
          "aes128-gcm@openssh.com"
          "aes256-ctr"
          "aes128-ctr"
        ];
        macs = [
          "hmac-sha2-512-etm@openssh.com"
          "hmac-sha2-256-etm@openssh.com"
        ];
        kexAlgorithms = [
          "curve25519-sha256"
          "curve25519-sha256@libssh.org"
          "ecdh-sha2-nistp521"
          "ecdh-sha2-nistp384"
          "ecdh-sha2-nistp256"
        ];
        clientAliveInterval = 600;
        clientAliveCountMax = 0;
      };
    };

    # A.5 Log Retention
    logRetention = mkOption {
      description = "Retention targets for each distinct log stream. systemd journal at 365 days satisfies PCI; AI decision logs at 18 months satisfy EU AI Act Art. 12; policy docs at 6 years satisfy HIPAA §164.316(b).";
      type = types.submodule {
        options = {
          journalMaxRetention = mkOption { type = types.str; };
          journalMaxUse = mkOption { type = types.str; };
          journalForwardToSyslog = mkOption { type = types.bool; };
          aiDecisionLogs = mkOption { type = types.str; };
          policyDocs = mkOption { type = types.str; };
        };
      };
      default = {
        journalMaxRetention = "365day";
        journalMaxUse = "10G";
        journalForwardToSyslog = true;
        aiDecisionLogs = "18month";
        policyDocs = "6year";
      };
    };

    # A.6 Authentication and Account Policy
    auth = mkOption {
      description = "Password, lockout, session, and MFA policy — strictest applicable value across frameworks.";
      type = types.submodule {
        options = {
          passwordMinLength = mkOption { type = types.ints.positive; };
          passwordHistoryRemember = mkOption { type = types.ints.positive; };
          passwordMaxAgeDays = mkOption { type = types.ints.positive; };
          lockoutThreshold = mkOption { type = types.ints.positive; };
          lockoutUnlockTimeSeconds = mkOption { type = types.ints.positive; };
          lockoutFindIntervalSeconds = mkOption { type = types.ints.positive; };
          sessionIdleTimeoutSshSeconds = mkOption { type = types.ints.positive; };
          sessionIdleTimeoutShellSeconds = mkOption { type = types.ints.positive; };
          mfaScope = mkOption { type = types.str; };
          mfaMechanism = mkOption { type = types.listOf types.str; };
          sudoTimestampTimeoutMinutes = mkOption { type = types.ints.positive; };
        };
      };
      default = {
        passwordMinLength = 15;
        passwordHistoryRemember = 24;
        passwordMaxAgeDays = 60;
        lockoutThreshold = 5;
        lockoutUnlockTimeSeconds = 1800;
        lockoutFindIntervalSeconds = 900;
        sessionIdleTimeoutSshSeconds = 600;
        sessionIdleTimeoutShellSeconds = 600;
        mfaScope = "all-remote-admin";
        mfaMechanism = [ "totp-google-authenticator" "fido2-ed25519-sk" ];
        sudoTimestampTimeoutMinutes = 5;
      };
    };

    # A.7 Patching
    patching = mkOption {
      description = "Vulnerability remediation timelines keyed by severity.";
      type = types.attrsOf types.str;
      default = {
        critical = "30day";
        high = "90day";
        medium = "180day";
        zeroDayActivelyExploited = "72hour";
      };
    };

    # A.8 Scanning
    scanning = mkOption {
      description = "Scan cadence for each detection layer.";
      type = types.attrsOf types.str;
      default = {
        aideFileIntegrity = "hourly";
        vulnixCve = "weekly";
        nixStoreVerify = "daily";
        clamavFull = "weekly";
        lynisHardening = "monthly";
        openvasNetwork = "quarterly";
        pciSegmentation = "6month";
        complianceEvidence = "weekly+on-rebuild";
      };
    };

    # A.9 Encryption
    encryption = mkOption {
      description = "TLS, disk, and swap encryption policy.";
      type = types.submodule {
        options = {
          tlsMinVersion = mkOption { type = types.str; };
          tlsCiphers = mkOption { type = types.str; };
          diskEncryption = mkOption { type = types.str; };
          swapEncryption = mkOption { type = types.str; };
        };
      };
      default = {
        tlsMinVersion = "TLSv1.2";
        tlsCiphers = "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256";
        diskEncryption = "LUKS2-AES-256-XTS";
        swapEncryption = "luks-via-boot.initrd.luks.devices";
      };
    };

    # A.10 Kernel Module Blacklist
    kernelModuleBlacklist = mkOption {
      description = "Canonical boot.blacklistedKernelModules list. stig-baseline owns the option; no other module declares it. STIG list is the superset of all framework-specific lists.";
      type = types.listOf types.str;
      default = [
        "cramfs"
        "freevxfs"
        "jffs2"
        "hfs"
        "hfsplus"
        "squashfs"
        "udf"
        "dccp"
        "sctp"
        "rds"
        "tipc"
        "bluetooth"
        "btusb"
        "cfg80211"
        "mac80211"
        "firewire-core"
        "firewire-ohci"
        "firewire-sbp2"
        "firewire-net"
        "ohci1394"
        "sbp2"
        "dv1394"
        "raw1394"
        "video1394"
        "thunderbolt"
        "usb-storage"
        "uas"
        "pcspkr"
        "snd_pcsp"
        "floppy"
      ];
    };

    # A.11 tmpfiles Rules
    tmpfilesRules = mkOption {
      description = "Canonical systemd.tmpfiles.rules entries. audit-and-aide owns consolidation; no other module declares the same path.";
      type = types.listOf (types.submodule {
        options = {
          path = mkOption { type = types.str; };
          mode = mkOption { type = types.str; };
          user = mkOption { type = types.str; };
          group = mkOption { type = types.str; };
        };
      });
      default = [
        { path = "/var/lib/ollama"; mode = "0750"; user = "ollama"; group = "ollama"; }
        { path = "/var/lib/agent-runner"; mode = "0750"; user = "agent"; group = "agent"; }
        { path = "/var/lib/agent-runner/workspace"; mode = "0750"; user = "agent"; group = "agent"; }
        { path = "/var/lib/ai-services"; mode = "0750"; user = "ai-services"; group = "ai-services"; }
        { path = "/var/lib/ai-services/rag"; mode = "0750"; user = "ai-services"; group = "ai-services"; }
        { path = "/var/log/audit"; mode = "0700"; user = "root"; group = "root"; }
        { path = "/var/log/ai-audit"; mode = "0700"; user = "root"; group = "root"; }
        { path = "/var/log/sudo-io"; mode = "0700"; user = "root"; group = "root"; }
        { path = "/var/lib/compliance-evidence"; mode = "0750"; user = "root"; group = "root"; }
      ];
    };

    # A.12 AIDE Monitored Paths
    aidePaths = mkOption {
      description = "AIDE monitor paths. NixOS-aware; must never reference /usr/bin, /usr/sbin, /sbin, or /usr/lib.";
      type = types.listOf (types.submodule {
        options = {
          path = mkOption { type = types.str; };
          rule = mkOption { type = types.str; };
          purpose = mkOption { type = types.str; };
        };
      });
      default = [
        { path = "/run/current-system/sw/bin"; rule = "R+sha512"; purpose = "System binaries (NixOS equivalent of /usr/bin)"; }
        { path = "/run/current-system/sw/sbin"; rule = "R+sha512"; purpose = "System admin binaries"; }
        { path = "/etc"; rule = "R+sha512"; purpose = "System configuration"; }
        { path = "/boot"; rule = "R+sha512"; purpose = "Bootloader and kernel"; }
        { path = "/var/lib/ollama/models"; rule = "R+sha256"; purpose = "Model artifact integrity"; }
        { path = "/var/lib/ai-services"; rule = "R+sha512"; purpose = "Application data integrity"; }
        { path = "/nix/var/nix/profiles/system"; rule = "R+sha512"; purpose = "NixOS generation symlink"; }
      ];
    };

    # A.13 FIPS Mode Decision
    fips = mkOption {
      description = "FIPS mode stance. 'algorithm-compatible' restricts to FIPS-approved algorithms without claiming FIPS 140-2/3 validation; 'validated' requires a loaded FIPS provider and is currently unreachable on stock NixOS.";
      type = types.submodule {
        options = {
          mode = mkOption {
            type = types.enum [ "algorithm-compatible" "validated" ];
          };
          ed25519Allowed = mkOption { type = types.bool; };
        };
      };
      default = {
        mode = "algorithm-compatible";
        ed25519Allowed = true;
      };
    };

    # A.14 NixOS-Specific Options
    nixosOptions = mkOption {
      description = "Canonical values for frequently-referenced NixOS options. Each must be set exactly once — see ARCH-16 boundary lints.";
      type = types.submodule {
        options = {
          usersMutableUsers = mkOption { type = types.bool; };
          nixAllowedUsers = mkOption { type = types.listOf types.str; };
          systemdBootEditor = mkOption { type = types.bool; };
          ctrlAltDelUnit = mkOption { type = types.str; };
          coredumpStorage = mkOption { type = types.enum [ "none" "external" "journal" ]; };
          coredumpKernelPattern = mkOption { type = types.str; };
          wirelessEnable = mkOption { type = types.bool; };
          xserverEnable = mkOption { type = types.bool; };
        };
      };
      default = {
        usersMutableUsers = false;
        nixAllowedUsers = [ "admin" ];
        systemdBootEditor = false;
        ctrlAltDelUnit = "";
        coredumpStorage = "none";
        coredumpKernelPattern = "|/bin/false";
        wirelessEnable = false;
        xserverEnable = false;
      };
    };

    # A.15 Notify/Alert Service Template
    notifyTemplate = mkOption {
      description = "Template-unit conventions for notify-admin@.service. Uses systemd specifier %i, never the shell positional $1.";
      type = types.submodule {
        options = {
          instanceSpecifier = mkOption { type = types.str; };
          logPath = mkOption { type = types.str; };
        };
      };
      default = {
        instanceSpecifier = "%i";
        logPath = "/var/log/admin-alerts.log";
      };
    };

  };
}
