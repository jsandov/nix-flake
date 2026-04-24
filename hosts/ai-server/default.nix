{ lib, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "ai-server";

  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  time.timeZone = "UTC";

  # Primary operator. Policy (password length, lockout, session
  # timeouts, MFA scope) lives in canonical.auth and is consumed by
  # modules/accounts — this host only names who operates it. The
  # skeleton key below is a placeholder; replace with the real
  # ed25519 public key before first deploy.
  security.accounts.adminUser = {
    name = "admin";
    description = "Primary operator — key-based login only.";
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISKELETONSKELETONSKELETONSKELETONSKELETONPLACEHOLDER operator@skeleton"
    ];
  };

  system.stateVersion = "24.11";
}
