{ config, pkgs, lib, ... }:

# ---------------------------------------------------------------------------
# Node 6 — K3s server join (expansion control-plane slot) — 10.0.20.16
# ---------------------------------------------------------------------------

{
  networking.hostName = "homelab-node6";

  homelab.node = {
    mac = "TODO_REPLACE_WITH_MAC";
    ip  = "10.0.20.16/24";
  };

  services.k3s.extraFlags = lib.mkForce (toString [
    "--disable=traefik"
    "--disable=servicelb"
    "--disable=local-storage"
    "--node-ip=10.0.20.16"
    "--kubelet-arg=cgroup-driver=systemd"
  ]);

  # disko.devices.disk.main.device = "/dev/nvme0n1";
  users.users.root.openssh.authorizedKeys.keys = [];
}
