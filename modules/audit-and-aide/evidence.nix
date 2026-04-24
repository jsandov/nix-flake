{ config, lib, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;

  cfg = config.services.complianceEvidence;

  # Absolute tool paths. Prefer pkgs-prefixed store paths because the
  # broad-code FHS lint rejects any reference to legacy FHS bin
  # directories — and NixOS does not put these tools there anyway. The
  # two tools that do not ship as standalone packages in nixos-24.11
  # (nixos-rebuild, nixos-version) live under /run/current-system/sw/bin
  # at runtime; they are resolved through PATH inside the generated
  # script rather than hard-coded to a store path.
  nftBin = "${pkgs.nftables}/bin/nft";
  auditctlBin = "${pkgs.audit}/bin/auditctl";
  sshdBin = "${pkgs.openssh}/bin/sshd";
  cryptsetupBin = "${pkgs.cryptsetup}/bin/cryptsetup";
  sha256sumBin = "${pkgs.coreutils}/bin/sha256sum";
  getentBin = "${pkgs.glibc.bin}/bin/getent";
  nixBin = "${config.nix.package}/bin/nix";
  nixStoreBin = "${config.nix.package}/bin/nix-store";
  nixInfoBin = "${pkgs.nix-info}/bin/nix-info";

  # The default collector set maps 1:1 to docs/prd/prd.md §7.9. Future
  # framework modules (hipaa-evidence, pci-evidence, hitrust-evidence)
  # must leave this attrset intact and add their own entries under
  # distinct keys — do not mkForce-replace the core set.
  coreCollectors = {
    passwd = {
      description = "Local account inventory (getent passwd).";
      command = "${getentBin} passwd";
      outputFile = "getent-passwd.txt";
    };
    group = {
      description = "Local group inventory (getent group).";
      command = "${getentBin} group";
      outputFile = "getent-group.txt";
    };
    nftRuleset = {
      description = "Active nftables ruleset — firewall state of record.";
      command = "${nftBin} list ruleset";
      outputFile = "nft-ruleset.txt";
    };
    auditctlRules = {
      description = "Loaded kernel audit rules (auditctl -l).";
      command = "${auditctlBin} -l";
      outputFile = "auditctl-rules.txt";
    };
    systemClosure = {
      # Capped at 500 lines — the full closure can run to tens of
      # thousands of store paths on a fat AI host and balloons the
      # snapshot. 500 entries is enough to cross-reference top-level
      # packages during an audit; the full closure is reproducible
      # from the flake lock and the generation symlink anyway.
      description = "First 500 store-path requisites of /run/current-system.";
      command = "${nixStoreBin} --query --requisites /run/current-system | head -n 500";
      outputFile = "system-closure-top500.txt";
    };
    nixosGenerations = {
      description = "NixOS generation history — ties rebuilds to evidence.";
      command = "nixos-rebuild list-generations";
      outputFile = "nixos-generations.txt";
    };
    sshdConfig = {
      description = "Effective sshd configuration (sshd -T).";
      command = "${sshdBin} -T";
      outputFile = "sshd-effective.txt";
    };
    cryptsetupStatus = {
      # Best-effort per mapper device. `cryptsetup status` fails loudly
      # on non-LUKS mappers, so iterate and swallow the error; the exit
      # code is captured by the outer wrapper.
      description = "LUKS mapper status for every /dev/mapper/* device.";
      command = ''
        for dev in /dev/mapper/*; do
          [ -e "$dev" ] || continue
          name="$(basename "$dev")"
          [ "$name" = "control" ] && continue
          echo "=== $name ==="
          ${cryptsetupBin} status "$name" || true
        done
      '';
      outputFile = "cryptsetup-status.txt";
    };
    nixStoreVerify = {
      # --check-contents re-hashes every file and is prohibitively slow
      # on a store with GPU drivers and model weights. The signature /
      # hash-name check (default `nix-store --verify`) is what PCI /
      # HITRUST actually require and runs in seconds.
      description = "Store integrity via `nix-store --verify` (no --check-contents).";
      command = "${nixStoreBin} --verify";
      outputFile = "nix-store-verify.txt";
    };
    flakeMetadata = {
      # Wrapped with `|| true` because /root may not be where the flake
      # lives on a production host — the metadata read is aspirational
      # evidence, not a gate. Failure is recorded in the file, which is
      # itself covered by manifest.sha256.
      description = "Flake metadata (best-effort; empty if flake unreachable).";
      command = "${nixBin} flake metadata --json 2>&1 || true";
      outputFile = "flake-metadata.json";
    };
    nixosVersion = {
      description = "nixos-version output (channel, revision, codename).";
      command = "nixos-version";
      outputFile = "nixos-version.txt";
    };
    nixInfo = {
      description = "nix-info -m — platform + nixpkgs channel dump.";
      command = "${nixInfoBin} -m";
      outputFile = "nix-info.txt";
    };
    resolvedSettings = {
      # Not a command in the strict sense — copy the etc file that
      # ARCH-04 publishes into the snapshot so reviewers do not have
      # to cross-reference a running system to read it.
      description = "Copy of /etc/compliance/resolved-settings.yaml (ARCH-04).";
      command = "cat /etc/compliance/resolved-settings.yaml";
      outputFile = "resolved-settings.yaml";
    };
  };

  # The script collects every registered collector into a timestamped
  # directory, computes a sha256 manifest, and prunes old snapshots.
  # `nixos-rebuild` and `nixos-version` come from the live system
  # profile at /run/current-system/sw/bin — prepending that to PATH
  # keeps the broad FHS lint satisfied and reflects where these tools
  # actually live on NixOS.
  snapshotScript = pkgs.writeShellApplication {
    name = "compliance-evidence-snapshot";

    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.findutils
    ];

    text = ''
      set -euo pipefail

      export PATH="/run/current-system/sw/bin:$PATH"

      root="${cfg.directory}"
      stamp="$(date -u +%Y%m%d-%H%M%S)"
      snapdir="$root/$stamp"
      mkdir -p "$snapdir"
      chmod 0750 "$snapdir"

      run_collector() {
        local name="$1"
        local outfile="$2"
        local cmd="$3"
        # Capture stdout+stderr together — a failed collector's error
        # message IS the evidence.
        if ! bash -c "$cmd" >"$snapdir/$outfile" 2>&1; then
          echo "[compliance-evidence] collector '$name' exited non-zero; output preserved." >&2
        fi
      }

      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: c: ''
          run_collector ${lib.escapeShellArg name} ${lib.escapeShellArg c.outputFile} ${lib.escapeShellArg c.command}
        '') cfg.collectors
      )}

      # Manifest: one sha256 per file, sorted for deterministic diffs.
      ( cd "$snapdir" && find . -type f ! -name manifest.sha256 -print0 \
          | sort -z \
          | xargs -0 ${sha256sumBin} > manifest.sha256 )
      chmod 0640 "$snapdir"/*

      # Retention: keep the N most recent snapshots, prune the rest.
      # Directory names sort lexicographically by timestamp so `sort`
      # ordered by name is equivalent to time order.
      keep=${toString cfg.retainSnapshots}
      mapfile -t all < <(find "$root" -mindepth 1 -maxdepth 1 -type d | sort)
      total=''${#all[@]}
      if (( total > keep )); then
        prune=$(( total - keep ))
        for ((i=0; i<prune; i++)); do
          rm -rf -- "''${all[i]}"
        done
      fi
    '';
  };

in
{
  # compliance-evidence — shared evidence generation framework (ARCH-10).
  #
  # Collects a point-in-time snapshot of the system's compliance posture
  # (account inventory, firewall ruleset, audit rules, store closure,
  # effective sshd config, LUKS mapper state, store integrity, flake
  # metadata, nixos-version, nix-info, resolved settings) into
  # /var/lib/compliance-evidence/YYYYMMDD-HHMMSS/, covered by a
  # manifest.sha256 that reviewers can re-verify after the fact.
  #
  # Cadence: weekly via systemd timer AND on every `nixos-rebuild
  # switch` via system.activationScripts. The weekly run gives a steady
  # beat of evidence even if rebuilds are rare; the activation hook
  # gives an exact "before vs. after" pair for every config change —
  # auditors expect both.
  #
  # Extension point: `services.complianceEvidence.collectors` is an
  # attrsOf-submodule, so future framework modules (hipaa-evidence,
  # pci-evidence, hitrust-evidence) register their own collectors by
  # appending attrs — no edits to this module required.
  #
  # Control families: NIST AU-6 / AU-12 (audit review, generation);
  # HIPAA §164.312(b) Audit Controls; PCI 10.7 (log retention & review);
  # HITRUST 06.e (information security review); STIG evidence
  # requirements for periodic attestation.
  #
  # Storage directory (/var/lib/compliance-evidence, 0750 root:root) is
  # declared in canonical.tmpfilesRules — do not redeclare here.

  options.services.complianceEvidence = {
    enable = mkEnableOption "shared compliance evidence snapshots";

    cadence = mkOption {
      type = types.str;
      default = "weekly";
      description = ''
        systemd OnCalendar expression for the periodic snapshot timer.
        Default tracks canonical.scanning.complianceEvidence = "weekly".
      '';
    };

    directory = mkOption {
      type = types.path;
      default = "/var/lib/compliance-evidence";
      description = ''
        Root directory for snapshots. Each run lands in a
        `YYYYMMDD-HHMMSS/` subdirectory. Mode/ownership are managed by
        canonical.tmpfilesRules (0750 root:root).
      '';
    };

    retainSnapshots = mkOption {
      type = types.ints.positive;
      default = 52;
      description = ''
        Maximum number of snapshots to keep. Older snapshots are pruned
        at the end of each run. Default 52 = one year of weekly runs.
      '';
    };

    collectors = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          description = mkOption {
            type = types.str;
            description = "Human-readable purpose of this collector.";
          };
          command = mkOption {
            type = types.str;
            description = ''
              Shell fragment whose combined stdout+stderr is captured
              into `outputFile`. Must reference tools by absolute store
              path — legacy FHS bin directories are rejected by the
              repo-wide broad-code lint.
            '';
          };
          outputFile = mkOption {
            type = types.str;
            description = ''
              File name (not path) relative to the snapshot directory.
              Must be unique across all registered collectors.
            '';
          };
        };
      });
      default = coreCollectors;
      description = ''
        Registered evidence collectors. This is the extension point:
        framework-specific modules (HIPAA, PCI, HITRUST) append their
        own entries rather than editing this module. Overriding an
        existing entry requires lib.mkForce to make the intent loud.
      '';
    };

    runOnActivation = mkOption {
      type = types.bool;
      default = true;
      description = ''
        When true, a snapshot runs during every `nixos-rebuild switch`
        via system.activationScripts, in addition to the weekly timer.
        Disable only if activation-time evidence is captured out-of-band.
      '';
    };
  };

  # The real wiring is gated on `cfg.enable`. The audit-and-aide
  # default.nix sets `services.complianceEvidence.enable = mkDefault
  # true` so the hook is on by default whenever this module is
  # imported; an operator can still override with `lib.mkForce false`.
  config = mkIf cfg.enable {

    environment = {
      # Expose the ARCH-04 resolved-settings YAML at a stable etc path
      # so the snapshot script (and any downstream reviewer tooling)
      # can read it without knowing where the flake lives on disk.
      etc."compliance/resolved-settings.yaml".source =
        ../../docs/resolved-settings.yaml;

      # Snapshot binary in the system profile so operators can run an
      # ad-hoc snapshot during a review.
      systemPackages = [ snapshotScript ];
    };

    systemd = {
      services.compliance-evidence-snapshot = {
        description = "Compliance evidence snapshot (core framework).";
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          ExecStart = "${snapshotScript}/bin/compliance-evidence-snapshot";
        };
      };

      timers.compliance-evidence-snapshot = {
        description = "Periodic compliance evidence snapshot.";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.cadence;
          # Persistent: if the host was off at the scheduled moment,
          # run as soon as it boots. Evidence gaps are audit findings.
          Persistent = true;
          # Small randomised delay so the run does not collide with
          # other weekly jobs on the same calendar minute.
          RandomizedDelaySec = "15min";
        };
      };
    };

    # Activation hook: capture a snapshot on every `nixos-rebuild
    # switch`. deps = [ ] runs in the default phase; the snapshot only
    # reads state and writes under /var/lib/compliance-evidence, which
    # is created by tmpfiles ahead of activation. `|| true` keeps a
    # collector failure from aborting the rebuild; the failure is
    # itself part of the captured evidence.
    system.activationScripts.complianceEvidenceOnRebuild =
      mkIf cfg.runOnActivation {
        text = ''
          ${snapshotScript}/bin/compliance-evidence-snapshot || true
        '';
        deps = [ ];
      };
  };
}
