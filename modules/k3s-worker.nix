{ config, pkgs, lib, ... }:

# ---------------------------------------------------------------------------
# K3s agent (worker) module — for expansion nodes (node7+)
#
# Difference from k3s-server-join.nix:
#   role = "agent"   → no etcd, no API server, pure workload
#   role = "server"  → control-plane + workload (for HA cluster)
#
# Use this module for dedicated worker nodes.
# Minimal firewall: only kubelet needed (no etcd/API server ports).
# ---------------------------------------------------------------------------

{
  services.k3s = {
    enable     = true;
    role       = "agent";
    serverAddr = "https://10.0.20.11:6443";

    # CRITICAL: token via sops, never inline (gotcha #2)
    tokenFile = config.sops.secrets."k3s/token".path;

    extraFlags = toString [
      "--kubelet-arg=cgroup-driver=systemd"
      "--node-label=role=worker"
    ];
  };

  # Same sops secret as control-plane nodes
  sops.secrets."k3s/token" = {
    sopsFile     = ../secrets/secrets.yaml;
    owner        = "root";
    group        = "root";
    mode         = "0400";
    restartUnits = [ "k3s.service" ];
  };

  # Worker nodes don't need etcd/API server ports
  # UDP 8472 (Flannel VXLAN) is already open via common/default.nix
  networking.firewall.allowedTCPPorts = [
    10250  # kubelet metrics (voor monitoring en kubectl logs/exec)
  ];

  # Do NOT open etcd/API ports on worker nodes
  # 6443, 2379, 2380 are only needed on control-plane nodes
}
