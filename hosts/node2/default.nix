{ config, pkgs, lib, ... }:

# ---------------------------------------------------------------------------
# Node 2 — K3s server join  (10.0.20.12)
# HP EliteDesk 800 G4 Mini
# ---------------------------------------------------------------------------

{
  networking.hostName = "homelab-node2";

  # TODO: replace "eno1" with actual NIC name
  networking.interfaces."eno1" = {
    useDHCP = false;
    ipv4.addresses = [{
      address      = "10.0.20.12";
      prefixLength = 24;
    }];
  };

  networking.defaultGateway = "10.0.20.1";

  # Override node-IP for K3s (appended to extraFlags from k3s-server-join.nix)
  services.k3s.extraFlags = lib.mkForce (toString [
    "--disable=traefik"
    "--disable=servicelb"
    "--disable=local-storage"
    "--node-ip=10.0.20.12"
    "--flannel-iface=eno1"  # TODO: verify interface name
    "--kubelet-arg=cgroup-driver=systemd"
  ]);

  # TODO: verify disk device (lsblk)
  # disko.devices.disk.main.device = "/dev/nvme0n1";

  users.users.root.openssh.authorizedKeys.keys = [
    # TODO: add your SSH public key(s)
  ];
}
