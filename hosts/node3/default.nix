{ config, pkgs, lib, ... }:

# ---------------------------------------------------------------------------
# Node 3 — K3s server join — 10.0.20.13
# HP EliteDesk 800 G6 Mini — i5-10500, 16 GB
# ---------------------------------------------------------------------------

{
  networking.hostName = "homelab-node3";

  homelab.node = {
    mac = "a8:b1:3b:93:77:e7";
    ip  = "10.0.20.13/24";
  };

  services.k3s.extraFlags = lib.mkForce (toString [
    "--disable=traefik"
    "--disable=servicelb"
    "--disable=local-storage"
    "--node-ip=10.0.20.13"
    "--kubelet-arg=cgroup-driver=systemd"
  ]);

  homelab.node.disk = "/dev/nvme0n1";
  users.users.root.openssh.authorizedKeys.keys = [];
}
