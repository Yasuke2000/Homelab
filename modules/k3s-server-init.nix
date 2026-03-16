{ config, pkgs, lib, ... }:

# ---------------------------------------------------------------------------
# K3s cluster-init — NODE 1 ONLY (10.0.20.11)
#
# This module bootstraps the embedded etcd HA cluster.
# Node2 and Node3 use k3s-server-join.nix to join.
#
# CRITICAL gotchas:
#   #2 — tokenFile via sops-nix, NEVER inline token
#   #5 — use services.k3s.* options, NEVER the bash install script
# ---------------------------------------------------------------------------

{
  services.k3s = {
    enable = true;
    role   = "server";

    # clusterInit bootstraps a new embedded etcd cluster.
    # Only set this on the FIRST node. Never on join nodes.
    clusterInit = true;

    # CRITICAL: token must come from sops, never hardcoded
    # See: gotchas.md #2
    tokenFile = config.sops.secrets."k3s/token".path;

    extraFlags = toString [
      # Disable built-ins — we deploy our own
      "--disable=traefik"          # our Traefik v3 via ArgoCD
      "--disable=servicelb"        # MetalLB handles LoadBalancer
      "--disable=local-storage"    # Longhorn handles PVCs

      # Node addressing
      "--node-ip=10.0.20.11"
      "--advertise-address=10.0.20.11"

      # TLS SANs: add all node IPs so kubectl works from any node
      "--tls-san=10.0.20.11"
      "--tls-san=10.0.20.12"
      "--tls-san=10.0.20.13"
      # TODO: add your VIP or domain if you front the API server with HAProxy
      # "--tls-san=k8s.yourdomain.com"

      # Networking
      # TODO: verify interface name on your hardware (ip link show)
      #   HP EliteDesk 800 G4 onboard NIC is typically: eno1 or enp3s0
      "--flannel-iface=eno1"

      # etcd metrics for Prometheus
      "--etcd-expose-metrics=true"

      # Use systemd cgroup driver (required for NixOS)
      "--kubelet-arg=cgroup-driver=systemd"
    ];
  };

  # sops secret: K3s cluster join token
  # Create with: sops secrets/secrets.yaml
  # Key path in yaml: k3s.token
  sops.secrets."k3s/token" = {
    sopsFile = ../secrets/secrets.yaml;
    owner    = "root";
    group    = "root";
    mode     = "0400";
    # Token must exist before k3s starts
    restartUnits = [ "k3s.service" ];
  };

  # Allow other nodes to join
  networking.firewall.allowedTCPPorts = [
    2379   # etcd client (already in common, explicit here for clarity)
    2380   # etcd peer
  ];

  # K3s writes kubeconfig here — make it readable for ops user
  # TODO: replace "david" with your actual ops username
  systemd.tmpfiles.rules = [
    "d /etc/rancher/k3s 0755 root root -"
  ];
}
