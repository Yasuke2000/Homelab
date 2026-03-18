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

      # Modules shared by every node
      baseModules = [
        disko.nixosModules.disko
        sops-nix.nixosModules.sops
        ./common
        ./modules/disk-config.nix
        ./modules/networking.nix
      ];
    in
    {
      # --- NixOS configurations for each node ---
      nixosConfigurations = {

        # Control-plane nodes (HA embedded etcd)
        node1 = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = baseModules ++ [
            ./modules/k3s-server-init.nix
            ./hosts/node1
          ];
        };

        node2 = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = baseModules ++ [
            ./modules/k3s-server-join.nix
            ./hosts/node2
          ];
        };

        node3 = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = baseModules ++ [
            ./modules/k3s-server-join.nix
            ./hosts/node3
          ];
        };

        # Expansion control-plane slots (node4-6 = server-join, same as node2/3)
        node4 = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = baseModules ++ [
            ./modules/k3s-server-join.nix
            ./hosts/node4
          ];
        };

        node5 = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = baseModules ++ [
            ./modules/k3s-server-join.nix
            ./hosts/node5
          ];
        };

        node6 = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = baseModules ++ [
            ./modules/k3s-server-join.nix
            ./hosts/node6
          ];
        };

        # Dedicated worker slots (node7-9 = agent only, no etcd/API server)
        node7 = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = baseModules ++ [
            ./modules/k3s-worker.nix
            ./hosts/node7
          ];
        };

        node8 = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = baseModules ++ [
            ./modules/k3s-worker.nix
            ./hosts/node8
          ];
        };

        node9 = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = baseModules ++ [
            ./modules/k3s-worker.nix
            ./hosts/node9
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
          ssh-to-age
          nixos-anywhere.packages.${system}.nixos-anywhere
        ];
      };
    };
}
