{
  description = "Compliance-mapped NixOS AI server — LAN-only, hardened, six-module layout.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    sops-nix = {
      # Pinned to the last commit before sops-install-secrets required
      # buildGo125Module (2026-02-04). nixos-24.11 nixpkgs ships Go 1.24,
      # so newer sops-nix breaks eval. Revisit when we bump nixpkgs to
      # 25.05 or later. See raw/sops-nix-skeleton-integration.md.
      url = "github:Mic92/sops-nix/3b4a369df9dd6ee171a7ea4448b50e2528faf850";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      # Pinned by commit SHA — never `@main` for inputs that gate the
      # build (see nixos-gotchas #15 + lessons-learned 26). Commit as of
      # 2026-04-21. Bump deliberately; audit the diff for breaking
      # changes to `boot.lanzaboote.*` option names before rotating.
      url = "github:nix-community/lanzaboote/4eda91dd5abd2157a2c7bfb33142fc64da668b0a";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, sops-nix, lanzaboote, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations.ai-server = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          sops-nix.nixosModules.sops
          lanzaboote.nixosModules.lanzaboote
          ./hosts/ai-server
          ./modules/canonical
          ./modules/meta
          ./modules/secrets
          ./modules/stig-baseline
          ./modules/gpu-node
          ./modules/lan-only-network
          ./modules/audit-and-aide
          ./modules/accounts
          ./modules/agent-sandbox
          ./modules/ai-services
        ];
      };

      nixosModules = {
        canonical = ./modules/canonical;
        meta = ./modules/meta;
        secrets = ./modules/secrets;
        stig-baseline = ./modules/stig-baseline;
        gpu-node = ./modules/gpu-node;
        lan-only-network = ./modules/lan-only-network;
        audit-and-aide = ./modules/audit-and-aide;
        accounts = ./modules/accounts;
        agent-sandbox = ./modules/agent-sandbox;
        ai-services = ./modules/ai-services;
      };

      formatter.${system} = pkgs.nixfmt-rfc-style;
    };
}
