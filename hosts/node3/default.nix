{ config, pkgs, lib, ... }:

# ---------------------------------------------------------------------------
# Node 3 — K3s server join — 10.0.20.13
# HP EliteDesk 800 G4 Mini
# ---------------------------------------------------------------------------

{
  networking.hostName = "homelab-node3";

  homelab.node = {
    mac = "TODO_REPLACE_WITH_MAC";
    ip  = "10.0.20.13/24";
  };

  services.k3s.extraFlags = lib.mkForce (toString [
    "--disable=traefik"
    "--disable=servicelb"
    "--disable=local-storage"
    "--node-ip=10.0.20.13"
    "--kubelet-arg=cgroup-driver=systemd"
  ]);

  homelab.node.disk = "TODO_REPLACE_WITH_DISK";
  users.users.root.openssh.authorizedKeys.keys = [];
}
