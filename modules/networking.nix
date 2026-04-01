{ config, lib, ... }:

# ---------------------------------------------------------------------------
# Shared networking module — systemd-networkd with MAC-based NIC matching
#
# Advantages over networking.interfaces:
#   - Works regardless of interface name (eno1, enp3s0, eth0, ...)
#   - NixOS Wiki 2025 recommended approach
#   - Interface name does NOT need to be known before deploy
#
# Usage in hosts/<node>/default.nix:
#   homelab.node.mac = "aa:bb:cc:dd:ee:ff";  # after hardware discovery
#   homelab.node.ip  = "10.0.20.11/24";
# ---------------------------------------------------------------------------

{
  options.homelab.node = {
    mac = lib.mkOption {
      type        = lib.types.str;
      default     = "TODO_REPLACE_WITH_MAC";
      description = ''
        MAC address of the primary NIC.
        Fill in after hardware discovery:
          ip link show | grep -A1 "state UP" | grep "link/ether" | awk "{print \$2}"
        Or via collect-hardware-info.sh or smart-deploy.sh.
      '';
      example = "aa:bb:cc:dd:ee:ff";
    };

    ip = lib.mkOption {
      type        = lib.types.str;
      description = "Static IP address with prefix length (CIDR notation).";
      example     = "10.0.20.11/24";
    };

    disk = lib.mkOption {
      type        = lib.types.str;
      default     = "TODO_REPLACE_WITH_DISK";
      description = ''
        Primary disk device path.
        HP EliteDesk 800 G4 NVMe  → /dev/nvme0n1
        HP EliteDesk 800 G4 SATA  → /dev/sda
        Fill in after hardware discovery:
          lsblk -dpno NAME,SIZE | grep -v 'loop\|sr' | sort -k2 -hr | head -1
        Or via smart-deploy.sh (automatic).
      '';
      example = "/dev/nvme0n1";
    };
  };

  config = {
    # systemd-networkd replaces scripted networking
    networking.useNetworkd = true;
    networking.useDHCP     = false;
    systemd.network.enable = true;

    # Match primary NIC by MAC address — works on any hardware
    systemd.network.networks."10-lan" = {
      matchConfig = {
        MACAddress = config.homelab.node.mac;
        Type       = "ether";
      };
      address = [ config.homelab.node.ip ];
      routes  = [{
        routeConfig = {
          Gateway      = "10.0.20.1";
          GatewayOnLink = true;
        };
      }];
      networkConfig = {
        DNS          = [ "10.0.20.1" "1.1.1.1" ];
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };
}
