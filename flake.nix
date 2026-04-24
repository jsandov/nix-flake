{
  description = "Compliance-mapped NixOS AI server — LAN-only, hardened, six-module layout.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, sops-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations.ai-server = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          sops-nix.nixosModules.sops
          ./hosts/ai-server
          ./modules/canonical
          ./modules/secrets
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
        secrets = ./modules/secrets;
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
