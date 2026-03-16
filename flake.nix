{
  description = "Sovereign bare-metal NixOS homelab — K3s HA cluster";

  inputs = {
    # NixOS 25.05 stable
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    # nixos-anywhere: deploy NixOS over SSH to bare metal
    nixos-anywhere.url = "github:nix-community/nixos-anywhere";
    nixos-anywhere.inputs.nixpkgs.follows = "nixpkgs";

    # disko: declarative disk partitioning
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # sops-nix: secrets management with age encryption
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixos-anywhere, disko, sops-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Shared specialArgs passed to every host
      specialArgs = {
        inherit self;
      };
    in
    {
      # --- NixOS configurations for each node ---
      nixosConfigurations = {

        node1 = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            ./common
            ./modules/disk-config.nix
            ./modules/k3s-server-init.nix
            ./hosts/node1
          ];
        };

        node2 = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            ./common
            ./modules/disk-config.nix
            ./modules/k3s-server-join.nix
            ./hosts/node2
          ];
        };

        node3 = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            ./common
            ./modules/disk-config.nix
            ./modules/k3s-server-join.nix
            ./hosts/node3
          ];
        };

      };

      # --- Dev shell: tools needed on your workstation ---
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          kubectl
          kubernetes-helm
          k9s
          sops
          age
          nixos-anywhere.packages.${system}.nixos-anywhere
        ];
      };
    };
}
