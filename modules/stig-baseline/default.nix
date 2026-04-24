{ config, lib, pkgs, ... }:
let
  cfg = config.security.secureBoot;
in
{
  # stig-baseline — OS foundation. Boot integrity, kernel hardening,
  # coredump suppression, blacklisted modules, tmpfs hardening.
  #
  # Consumes canonical nixosOptions.* for settings that must match
  # Appendix A. Secure Boot itself is gated behind
  # `security.secureBoot.enable` (default false) so CI / skeleton
  # deployments evaluate without requiring sbctl keys. A real
  # deployment flips the flag to true and provisions `/var/lib/sbctl`
  # before first `nixos-rebuild switch`.
  #
  # Control families: NIST AC/IA/CM/SC/SI; HIPAA Access/Audit/Auth;
  # PCI Req 2/5/6/8; STIG primary.
  #
  # Implementation tracked across INFRA-03..INFRA-07, INFRA-11..INFRA-13,
  # ARCH-09 (this PR). AIDE is owned by INFRA-09 in audit-and-aide.

  options.security.secureBoot = {
    enable = lib.mkEnableOption ''
      UEFI Secure Boot via lanzaboote. When off (default), the host uses
      systemd-boot and lanzaboote is dormant; `nix eval` can validate
      the flake on any system regardless of sbctl provisioning. When
      on, the host must have `/var/lib/sbctl` populated with a key
      enrolled in UEFI DB before `nixos-rebuild switch` — otherwise the
      next boot fails Secure Boot verification.
    '';

    pkiBundle = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sbctl";
      description = "Path to the sbctl PKI bundle. Operator provisions this out-of-band before enabling Secure Boot.";
    };
  };

  config = lib.mkMerge [

    # Unconditional hardening — applies whether or not Secure Boot is on.
    # These are canonical values from Appendix A.14 and A.10.
    {
      # Bootloader editor lockdown (A.14)
      boot.loader.systemd-boot.editor =
        config.canonical.nixosOptions.systemdBootEditor;

      # Disable Ctrl-Alt-Del reboot (A.14)
      systemd.ctrlAltDelUnit = config.canonical.nixosOptions.ctrlAltDelUnit;

      # Core dump suppression (A.14) — keeps ePHI/CHD out of on-disk
      # dumps. Two-layer: systemd-coredump storage off, kernel pattern
      # routes any fallback to /bin/false.
      systemd.coredump.extraConfig =
        "Storage=${config.canonical.nixosOptions.coredumpStorage}";
      boot.kernel.sysctl."kernel.core_pattern" =
        config.canonical.nixosOptions.coredumpKernelPattern;

      # Kernel module blacklist (A.10) — drives from canonical.
      boot.blacklistedKernelModules = config.canonical.kernelModuleBlacklist;

      # Tmpfs hardening — nosuid,nodev,noexec on /tmp. NixOS's
      # `boot.tmp.useTmpfs = true` mounts /tmp as tmpfs but does NOT
      # include noexec by default. Explicit fileSystems entry instead,
      # so we own the options list. /dev/shm is managed by util-linux
      # defaults (nosuid,nodev); extending to noexec via a remount unit
      # is deliberately deferred — many legitimate apps use /dev/shm
      # for executable buffers and breaking them for a single-operator
      # system adds operational cost without blocking any modelled threat.
      fileSystems."/tmp" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [ "defaults" "size=50%" "mode=1777" "nosuid" "nodev" "noexec" ];
      };

      # Disable wireless (canonical A.14 + lan-only-network charter)
      networking.wireless.enable =
        config.canonical.nixosOptions.wirelessEnable;

      # Headless — no GUI
      services.xserver.enable = config.canonical.nixosOptions.xserverEnable;

      # Immutable user accounts
      users.mutableUsers = config.canonical.nixosOptions.usersMutableUsers;

      # nix-daemon ACL
      nix.settings.allowed-users =
        config.canonical.nixosOptions.nixAllowedUsers;
    }

    # Secure Boot via lanzaboote — opt-in.
    (lib.mkIf cfg.enable {
      # Lanzaboote replaces systemd-boot. The host default module sets
      # systemd-boot.enable via lib.mkDefault; mkForce here overrides
      # without conflict because priority is higher.
      boot.loader.systemd-boot.enable = lib.mkForce false;

      boot.lanzaboote = {
        enable = true;
        pkiBundle = cfg.pkiBundle;
      };

      # sbctl exposed for key management. Operator runs:
      #   sudo sbctl create-keys
      #   sudo sbctl enroll-keys --microsoft
      # before first boot with Secure Boot enabled.
      environment.systemPackages = [ pkgs.sbctl ];

      # Emergency / rescue targets require root authentication. NixOS
      # default already enforces this via sulogin on the emergency unit;
      # documenting the requirement here keeps the control traceable in
      # evidence dumps even though no explicit config is needed.
      # (If a future NixOS change weakens the default, the intent is
      # captured and the gap will be caught by evidence review.)
    })

  ];
}
