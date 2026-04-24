{
  description = "Compliance-mapped NixOS AI server — LAN-only, hardened, six-module layout.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs =
    { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations.ai-server = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./hosts/ai-server
          ./modules/canonical
          ./modules/stig-baseline
          ./modules/gpu-node
          ./modules/lan-only-network
          ./modules/audit-and-aide
          ./modules/agent-sandbox
          ./modules/ai-services
        ];
      };

      nixosModules = {
        canonical = ./modules/canonical;
        stig-baseline = ./modules/stig-baseline;
        gpu-node = ./modules/gpu-node;
        lan-only-network = ./modules/lan-only-network;
        audit-and-aide = ./modules/audit-and-aide;
        agent-sandbox = ./modules/agent-sandbox;
        ai-services = ./modules/ai-services;
      };

      formatter.${system} = pkgs.nixfmt-rfc-style;
    };
}
