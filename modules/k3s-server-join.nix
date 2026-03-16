{ config, pkgs, lib, ... }:

# ---------------------------------------------------------------------------
# K3s server-join — NODE 2 and NODE 3
#
# Joins an existing embedded etcd cluster bootstrapped by node1.
# The host-specific IP is set in each host's default.nix via
# the `networking.interfaces` option.
#
# CRITICAL: tokenFile via sops-nix, NEVER inline. See: gotchas.md #2
# ---------------------------------------------------------------------------

{
  services.k3s = {
    enable = true;
    role   = "server";   # server = control-plane + worker

    # Point to node1 which ran clusterInit
    serverAddr = "https://10.0.20.11:6443";

    # CRITICAL: token from sops, never inline
    tokenFile = config.sops.secrets."k3s/token".path;

    extraFlags = toString [
      # Mirror the same disabled built-ins as the init node
      "--disable=traefik"
      "--disable=servicelb"
      "--disable=local-storage"

      # TODO: each host overrides --node-ip in its own default.nix
      # This is done via extraFlags concat — see hosts/node2/default.nix

      # TODO: verify interface name (ip link show)
      "--flannel-iface=eno1"

      "--kubelet-arg=cgroup-driver=systemd"
    ];
  };

  # Same sops secret as init node — same token for the whole cluster
  sops.secrets."k3s/token" = {
    sopsFile     = ../secrets/secrets.yaml;
    owner        = "root";
    group        = "root";
    mode         = "0400";
    restartUnits = [ "k3s.service" ];
  };
}
