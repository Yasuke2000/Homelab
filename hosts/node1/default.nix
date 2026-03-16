{ config, pkgs, lib, ... }:

# ---------------------------------------------------------------------------
# Node 1 — K3s cluster-init  (10.0.20.11)
# HP EliteDesk 800 G4 Mini
# ---------------------------------------------------------------------------

{
  networking.hostName = "homelab-node1";

  # Static IP on VLAN 20
  # TODO: replace "eno1" with actual NIC name (run: ip link show)
  # TODO: replace MAC address below with actual MAC (run: ip link show eno1)
  networking.interfaces."eno1" = {
    useDHCP = false;
    ipv4.addresses = [{
      address      = "10.0.20.11";
      prefixLength = 24;
    }];
  };

  networking.defaultGateway = "10.0.20.1";

  # Pass node-specific IP to K3s (extends extraFlags from k3s-server-init.nix)
  # This is already set in the init module but kept here for explicitness
  # services.k3s.extraFlags: "--node-ip=10.0.20.11" is set in k3s-server-init.nix

  # Node-specific disk device override (if different from modules/disk-config.nix)
  # TODO: verify disk device name (run: lsblk)
  #   NVMe → /dev/nvme0n1
  #   SATA SSD → /dev/sda
  # Uncomment and set below to override the default in disk-config.nix:
  # disko.devices.disk.main.device = "/dev/nvme0n1";

  # SSH authorized keys for this node
  users.users.root.openssh.authorizedKeys.keys = [
    # TODO: add your SSH public key(s)
    # "ssh-ed25519 AAAA... your-key-comment"
  ];

  # Optional: local ops user (non-root)
  # TODO: set a username and add your SSH key
  # users.users.david = {
  #   isNormalUser   = true;
  #   extraGroups    = [ "wheel" ];
  #   openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
  # };
  # security.sudo.wheelNeedsPassword = false;
}
