{ config, pkgs, lib, ... }:

# ---------------------------------------------------------------------------
# K3s agent (worker) module — voor uitbreidingsnodes (node4+)
#
# Verschil met k3s-server-join.nix:
#   role = "agent"   → geen etcd, geen API server, puur workload
#   role = "server"  → control-plane + workload (voor HA cluster)
#
# Gebruik dit module voor dedicated worker nodes.
# Minimale firewall: alleen kubelet nodig (geen etcd/API server ports).
# ---------------------------------------------------------------------------

{
  services.k3s = {
    enable     = true;
    role       = "agent";
    serverAddr = "https://10.0.20.11:6443";

    # KRITIEK: token via sops, nooit inline (gotcha #2)
    tokenFile = config.sops.secrets."k3s/token".path;

    extraFlags = toString [
      "--kubelet-arg=cgroup-driver=systemd"
      "--node-label=role=worker"
    ];
  };

  # Zelfde sops secret als control-plane nodes
  sops.secrets."k3s/token" = {
    sopsFile     = ../secrets/secrets.yaml;
    owner        = "root";
    group        = "root";
    mode         = "0400";
    restartUnits = [ "k3s.service" ];
  };

  # Worker nodes hebben geen etcd/API server ports nodig
  # UDP 8472 (Flannel VXLAN) staat al open via common/default.nix
  networking.firewall.allowedTCPPorts = [
    10250  # kubelet metrics (voor monitoring en kubectl logs/exec)
  ];

  # etcd/API poorten NIET openen op worker nodes
  # 6443, 2379, 2380 zijn alleen nodig op control-plane nodes
}
