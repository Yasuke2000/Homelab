{ config, pkgs, lib, ... }:

# ---------------------------------------------------------------------------
# Node 1 — K3s cluster-init (etcd leader) — 10.0.20.11
# HP ProDesk 400 G7 SFF — i7-10700, 16 GB
# ---------------------------------------------------------------------------

{
  networking.hostName = "homelab-node1";

  # MAC adres invullen na hardware discovery (zie issue #14):
  #   ip link show | grep -A1 "state UP" | grep "link/ether" | awk "{print $2}"
  # Of automatisch via: bash scripts/smart-deploy.sh <temp-ip> node1 server
  homelab.node = {
    mac = "b0:22:7a:2f:62:53";
    ip  = "10.0.20.11/24";
  };

  # Disk device overschrijven indien niet /dev/sda:
  homelab.node.disk = "/dev/nvme0n1";

  # Node-specifieke SSH keys (extra naast common/default.nix)
  users.users.root.openssh.authorizedKeys.keys = [];

  # ---------------------------------------------------------------------------
  # Tailscale subnet router — node1 advertises the home LAN to the tailnet
  # After nixos-rebuild: approve the route in Tailscale admin console:
  #   https://login.tailscale.com/admin/machines → node1 → Edit route settings
  # ---------------------------------------------------------------------------
  services.tailscale = {
    useRoutingFeatures = lib.mkForce "server";  # Override "client" from common
    extraUpFlags       = lib.mkForce [
      "--accept-dns=false"
      "--ssh"
      "--advertise-routes=10.0.20.0/24"          # Home LAN + MetalLB range
    ];
  };

  # IPv6 forwarding for subnet router (IPv4 forwarding already set in common)
  boot.kernel.sysctl = {
    "net.ipv6.conf.all.forwarding" = 1;
  };
}
