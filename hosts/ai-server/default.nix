{ lib, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "ai-server";

  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  time.timeZone = "UTC";

  system.stateVersion = "24.11";
}
