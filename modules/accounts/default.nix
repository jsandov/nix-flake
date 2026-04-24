{ config, lib, pkgs, ... }:
let
  inherit (lib) mkIf mkOption types;

  cfg = config.security.accounts;
  authPolicy = config.canonical.auth;

  # Absolute tool paths. NixOS does not populate /usr/bin, /usr/sbin,
  # or /sbin — the broad-code FHS lint rejects them anyway. `chage`
  # lives in pkgs.shadow; `getent` is the glibc split output; ssh-keygen
  # comes with openssh. See modules/audit-and-aide/evidence.nix for the
  # same pattern.
  getentBin = "${pkgs.glibc.bin}/bin/getent";
  sshKeygenBin = "${pkgs.openssh}/bin/ssh-keygen";
  chageBin = "${pkgs.shadow}/bin/chage";

  # Snapshot of canonical auth policy embedded into the access-review
  # report. lib.generators.toPretty renders it as readable Nix so the
  # reviewer sees exactly what values the module was configured with
  # at evaluation time — no ambiguity between "policy on paper" and
  # "policy in force".
  canonicalAuthSnapshot =
    lib.generators.toPretty { } {
      inherit (authPolicy)
        passwordMinLength
        passwordMaxAgeDays
        passwordHistoryRemember
        lockoutThreshold
        lockoutUnlockTimeSeconds
        sessionIdleTimeoutSshSeconds
        mfaScope
        mfaMechanism
        sudoTimestampTimeoutMinutes
        ;
    };

  # The access-review collector runs inside the ARCH-10 snapshot
  # service (root, oneshot). It emits:
  #   - the canonical auth policy in force (policy-of-record)
  #   - getent passwd filtered to the declared admin users
  #   - SSH key fingerprints for every authorized_keys entry
  #   - chage -l aging output per admin user
  # Combined output lands in access-review.txt inside the snapshot
  # directory. The snapshot already SHA-256-manifests every file, so
  # no extra tamper-seal work is needed here.
  accessReviewScript = pkgs.writeShellApplication {
    name = "compliance-access-review";
    runtimeInputs = [ pkgs.bash pkgs.coreutils ];
    text = ''
      set -euo pipefail

      admin_user=${lib.escapeShellArg cfg.adminUser.name}

      echo "=== canonical.auth policy (evaluated at config time) ==="
      printf '%s\n' ${lib.escapeShellArg canonicalAuthSnapshot}
      echo

      echo "=== getent passwd — declared admin accounts ==="
      ${getentBin} passwd "$admin_user" || echo "[access-review] $admin_user: no passwd entry (host not yet activated?)"
      echo

      echo "=== authorized_keys fingerprints — $admin_user ==="
      ${lib.concatStringsSep "\n" (
        map (key: ''
          printf '%s\n' ${lib.escapeShellArg key} | ${sshKeygenBin} -lf - || true
        '') cfg.adminUser.authorizedKeys
      )}
      echo

      echo "=== chage -l — $admin_user password aging ==="
      ${chageBin} -l "$admin_user" || echo "[access-review] chage unavailable or $admin_user missing"
    '';
  };

in
{
  # accounts — declarative account lifecycle (ARCH-11).
  #
  # Names the interactive operators, pins them to key-based login only,
  # and registers the quarterly access-review collector with the
  # ARCH-10 compliance-evidence framework. Policy values
  # (password length, lockout threshold, session timeouts, MFA scope)
  # stay owned by `canonical.auth.*`; this module consumes them and
  # embeds the snapshot into the review report so the enforced policy
  # is visible to a reviewer without cross-referencing another file.
  #
  # `users.mutableUsers = false` is deliberately NOT redeclared here.
  # stig-baseline already sets it from
  # `config.canonical.nixosOptions.usersMutableUsers` (default false);
  # two modules declaring the same option value would either duplicate
  # intent or require mkForce gymnastics for zero benefit. The
  # invariant that the `users.allowNoPasswordLogin = true` skeleton
  # escape can now be removed is owned by THIS module existing: an
  # admin user with authorized_keys is declared in the host, so the
  # NixOS assertion that requires either root password or a wheel
  # user with keys is satisfied structurally.
  #
  # The admin user has `hashedPassword = "!"` — the single-char idiom
  # for "no valid password hash will ever match, login is key-only".
  # Matches the project stance that all remote admin access is SSH
  # + MFA (canonical.auth.mfaScope = "all-remote-admin"); there is no
  # password to rotate and no password to leak.
  #
  # The access-review collector runs inside the ARCH-10 snapshot
  # service rather than on its own timer: the snapshot framework IS
  # the cadence (weekly + on-rebuild). Adding a second timer would
  # double the operational surface and split evidence into two
  # directories; one review report per snapshot keeps all evidence
  # for a given point-in-time co-located under the same manifest.
  #
  # Control families:
  #   NIST AC-2 (Account Management), AC-2(3) (Disable Inactive
  #     Accounts), IA-2 (Identification & Authentication), IA-5
  #     (Authenticator Management).
  #   HIPAA §164.308(a)(3)(ii)(B) (Workforce Clearance),
  #     §164.308(a)(3)(ii)(C) (Termination Procedures),
  #     §164.308(a)(4)(ii)(B) (Access Authorization).
  #   PCI DSS 7 (Access Control), 8.1 (Identify Users),
  #     8.2 (Authenticate Users).
  #   HITRUST 01.* (Access Control domain).
  #   STIG primary Account Management findings.

  options.security.accounts = {
    adminUser = mkOption {
      description = ''
        Primary interactive operator. Declared as a single submodule,
        not a list, in v1 — multi-admin scenarios are deferred until a
        second operator actually exists (see compliant-nix-config-vault/
        raw/arch-11-account-lifecycle.md "Open follow-ups").
      '';
      type = types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "POSIX username. Must match canonical.ssh.allowUsers entry.";
          };
          description = mkOption {
            type = types.str;
            description = "GECOS description string; appears in getent passwd and access-review evidence.";
          };
          authorizedKeys = mkOption {
            type = types.listOf types.str;
            description = ''
              Inline SSH public keys authorized for this user. Public
              keys are not secrets — keeping them in the host
              expression (rather than in sops-nix) avoids the
              encrypt/decrypt roundtrip for material that anyone can
              read off the wire during SSH connection setup. SSH
              private keys for the operator belong on the operator's
              workstation, never in the flake.
            '';
          };
          groups = mkOption {
            type = types.listOf types.str;
            default = [ "wheel" ];
            description = ''
              Supplementary groups. Default [ "wheel" ] grants sudo;
              override per host if a non-wheel admin is needed.
            '';
          };
        };
      };
    };

    accessReviewEnable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        When true, the quarterly-access-review collector is registered
        with services.complianceEvidence.collectors. Disable only if
        a deployment captures access-review evidence out-of-band.
      '';
    };
  };

  config = {
    users.users.${cfg.adminUser.name} = {
      isNormalUser = true;
      description = cfg.adminUser.description;
      extraGroups = cfg.adminUser.groups;
      openssh.authorizedKeys.keys = cfg.adminUser.authorizedKeys;
      # Key-only login. "!" is an invalid password hash that matches
      # no input; crypt(3) will never produce it for any password.
      # Equivalent to "disabled" for password auth without leaving a
      # NULL field that some audit tooling treats as "passwordless".
      hashedPassword = "!";
    };

    # Register the access-review collector with the ARCH-10 framework.
    # This is the first real downstream consumer of the
    # `services.complianceEvidence.collectors` extension point —
    # validating that attrsOf-submodule was the right shape for
    # "framework modules contribute rows to a shared pipeline."
    services.complianceEvidence.collectors = mkIf cfg.accessReviewEnable {
      accessReview = {
        description = "Quarterly access review — admin inventory, SSH key fingerprints, password aging, canonical auth policy snapshot.";
        command = "${accessReviewScript}/bin/compliance-access-review";
        outputFile = "access-review.txt";
      };
    };
  };
}
