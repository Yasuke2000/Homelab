{ config, pkgs, lib, ... }:

# ---------------------------------------------------------------------------
# Node 7 — K3s worker (dedicated agent, no etcd) — 10.0.20.17
# ---------------------------------------------------------------------------

{
  networking.hostName = "homelab-node7";

  homelab.node = {
    mac = "TODO_REPLACE_WITH_MAC";
    ip  = "10.0.20.17/24";
  };

  # Worker: override node-ip (k3s-worker.nix sets the base extraFlags)
  services.k3s.extraFlags = lib.mkForce (toString [
    "--kubelet-arg=cgroup-driver=systemd"
    "--node-label=role=worker"
    "--node-ip=10.0.20.17"
  ]);

  homelab.node.disk = "TODO_REPLACE_WITH_DISK";
  users.users.root.openssh.authorizedKeys.keys = [];
}
