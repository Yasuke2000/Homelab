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
    mac = "TODO_REPLACE_WITH_MAC";  # Hardware discovery vereist
    ip  = "10.0.20.11/24";
  };

  # Disk device overschrijven indien niet /dev/sda:
  homelab.node.disk = "TODO_REPLACE_WITH_DISK";

  # Node-specifieke SSH keys (extra naast common/default.nix)
  users.users.root.openssh.authorizedKeys.keys = [];
}
