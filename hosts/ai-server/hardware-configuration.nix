{ lib, ... }:
{
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  boot.initrd.availableKernelModules = lib.mkDefault [ ];
  boot.kernelModules = lib.mkDefault [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
