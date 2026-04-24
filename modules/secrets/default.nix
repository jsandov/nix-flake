{ lib, ... }:
{
  # secrets — sops-nix integration and per-secret declarations.
  #
  # Every secret the system needs is declared here. Every other module
  # consumes via `config.sops.secrets.<name>.path` (e.g.,
  # `services.nginx.virtualHosts.<host>.sslCertificate =
  #   config.sops.secrets."tls/ai-server.crt".path;`). No module embeds
  # plaintext secrets; no secret appears in the world-readable Nix store.
  #
  # Project decision: sops-nix, not agenix. See MASTER-REVIEW action
  # plan item #5 and todos/01-architecture-and-cross-cutting.md ARCH-05
  # for the rationale. The "either/or" prose in the PRD has been removed.
  #
  # Age key provisioning (operator procedure, not in Nix):
  #   1. On a trusted workstation:  age-keygen -o ~/.config/sops/age/keys.txt
  #   2. Publish the public key (`age1...`) into the repository .sops.yaml
  #      recipient list so sops can encrypt for it.
  #   3. On the server: `/var/lib/sops-nix/key.txt` must contain the
  #      private age key. Provisioned via physical console or one-shot
  #      SSH during initial bring-up; rotated on compromise.
  #
  # Rotation schedule (from canonical + wiki/shared-controls/secrets-management):
  #   - TLS certs: annual, 90-day for PCI deployments
  #   - SSH host keys / LUKS passphrases / TOTP seeds / backup keys: on compromise
  #   - API tokens: quarterly

  sops = {
    # Path to the encrypted secrets file relative to this module. The
    # placeholder at /secrets/secrets.enc.yaml lets eval succeed; real
    # deployments replace its body with sops-encrypted content.
    defaultSopsFile = ../../secrets/secrets.enc.yaml;

    # Disable the eval-time SOPS format check so the skeleton's plain-text
    # placeholder does not fail CI. Real deployments that ship a proper
    # encrypted file can set this to true (or remove the line).
    validateSopsFiles = false;

    age = {
      # sops-nix decrypts using this age key at activation time. Path is
      # a string (not a Nix path) because the key lives on the host, not
      # in the repo. Must not be on a tmpfs that disappears on reboot
      # before stage-1 secret materialisation.
      keyFile = "/var/lib/sops-nix/key.txt";

      # Do not generate an age key automatically — operator provisions
      # via the procedure documented above. Automatic generation would
      # produce an age key in the Nix store, defeating the threat model.
      generateKey = false;
    };

    # Per-secret declarations. Names follow the scheme `<category>/<id>`.
    # Paths default to /run/secrets/<name> (a tmpfs); override `path`
    # only when a service reads a fixed filesystem location.
    secrets = {
      # TLS — Nginx front-end for the LAN-only reverse proxy.
      "tls/ai-server.crt" = {
        owner = "nginx";
        group = "nginx";
        mode = "0440";
      };
      "tls/ai-server.key" = {
        owner = "nginx";
        group = "nginx";
        mode = "0400";
      };

      # Syslog forwarding CA (remote rsyslog over RELP TLS).
      "tls/syslog-ca.pem" = {
        owner = "syslog";
        group = "syslog";
        mode = "0440";
      };

      # SSH host keys — set path to the conventional sshd location so
      # services.openssh.hostKeys can reference it directly.
      "ssh/host-ed25519-key" = {
        owner = "root";
        group = "root";
        mode = "0400";
        path = "/etc/ssh/ssh_host_ed25519_key";
      };

      # LUKS passphrase backup — for disaster recovery. Never used at
      # runtime; provisioned so the operator can unlock from an offline
      # vault if the physical keyslot is lost.
      "luks/passphrase-backup" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      # API tokens consumed by AI services.
      "api/ollama-control-token" = {
        owner = "ollama";
        group = "ollama";
        mode = "0400";
      };
      "api/ai-services-signing-key" = {
        owner = "ai-services";
        group = "ai-services";
        mode = "0400";
      };

      # TOTP seed for the admin account (google-authenticator PAM).
      # Path is /home/admin/.google_authenticator — the PAM module reads
      # from a fixed location.
      "totp/admin-google-authenticator" = {
        owner = "admin";
        group = "admin";
        mode = "0400";
        path = "/home/admin/.google_authenticator";
      };

      # Backup encryption key — separate from the LUKS passphrase so a
      # compromise of backups does not require rotating system disk
      # encryption.
      "backup/encryption-key" = {
        owner = "root";
        group = "root";
        mode = "0400";
      };

      # Placeholder for the syslog RELP shared secret if using PSK-based
      # authentication instead of mTLS. Kept declared so consumer modules
      # can reference it unconditionally; leave as `/dev/null`-sized in
      # secrets.enc.yaml when unused.
      "syslog/relp-psk" = {
        owner = "syslog";
        group = "syslog";
        mode = "0400";
      };
    };
  };

  # Make the rotation cadence surfaceable to evidence-generation (ARCH-10).
  # Not a sops-nix option — a local convention that ARCH-10 will read.
  options.secrets.rotationDays = lib.mkOption {
    type = lib.types.attrsOf lib.types.ints.positive;
    description = "Rotation cadence in days for each secret category. Zero means 'on compromise only'.";
    default = {
      tls = 90;
      ssh = 0;
      luks = 0;
      api = 90;
      totp = 0;
      backup = 0;
      syslog = 90;
    };
  };
}
