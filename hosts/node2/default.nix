{ config, pkgs, lib, ... }:

# ---------------------------------------------------------------------------
# Node 2 — K3s server join — 10.0.20.12
# HP EliteDesk 800 G5 Mini — i5-9500T, 16 GB
# ---------------------------------------------------------------------------

{
  networking.hostName = "homelab-node2";

  homelab.node = {
    mac = "30:24:a9:7d:8b:1e";
    ip  = "10.0.20.12/24";
  };

  # Node-specifiek --node-ip voor K3s (rest van flags in k3s-server-join.nix)
  services.k3s.extraFlags = lib.mkForce (toString [
    "--disable=traefik"
    "--disable=servicelb"
    "--disable=local-storage"
    "--node-ip=10.0.20.12"
    "--kubelet-arg=cgroup-driver=systemd"
  ]);

  homelab.node.disk = "/dev/nvme0n1";
  users.users.root.openssh.authorizedKeys.keys = [];
}
