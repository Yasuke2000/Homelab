{ config, pkgs, lib, ... }:

# ---------------------------------------------------------------------------
# Node 8 — K3s worker (dedicated agent, no etcd) — 10.0.20.18
# ---------------------------------------------------------------------------

{
  networking.hostName = "homelab-node8";

  homelab.node = {
    mac = "TODO_REPLACE_WITH_MAC";
    ip  = "10.0.20.18/24";
  };

  # Worker: override node-ip (k3s-worker.nix sets the base extraFlags)
  services.k3s.extraFlags = lib.mkForce (toString [
    "--kubelet-arg=cgroup-driver=systemd"
    "--node-label=role=worker"
    "--node-ip=10.0.20.18"
  ]);

  # disko.devices.disk.main.device = "/dev/nvme0n1";
  users.users.root.openssh.authorizedKeys.keys = [];
}
