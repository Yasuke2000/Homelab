{ config, pkgs, lib, ... }:

# ---------------------------------------------------------------------------
# Node 2 — K3s server join — 10.0.20.12
# HP EliteDesk 800 G5 Mini — i5-9500T, 16 GB
# ---------------------------------------------------------------------------

{
  networking.hostName = "homelab-node2";

  homelab.node = {
    mac = "TODO_REPLACE_WITH_MAC";
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

  homelab.node.disk = "TODO_REPLACE_WITH_DISK";
  users.users.root.openssh.authorizedKeys.keys = [];
}
