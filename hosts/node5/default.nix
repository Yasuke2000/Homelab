{ config, pkgs, lib, ... }:

# ---------------------------------------------------------------------------
# Node 5 — K3s server join (expansion control-plane slot) — 10.0.20.15
# ---------------------------------------------------------------------------

{
  networking.hostName = "homelab-node5";

  homelab.node = {
    mac = "TODO_REPLACE_WITH_MAC";
    ip  = "10.0.20.15/24";
  };

  services.k3s.extraFlags = lib.mkForce (toString [
    "--disable=traefik"
    "--disable=servicelb"
    "--disable=local-storage"
    "--node-ip=10.0.20.15"
    "--kubelet-arg=cgroup-driver=systemd"
  ]);

  # disko.devices.disk.main.device = "/dev/nvme0n1";
  users.users.root.openssh.authorizedKeys.keys = [];
}
