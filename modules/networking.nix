{ config, lib, ... }:

# ---------------------------------------------------------------------------
# Shared networking module — systemd-networkd met MAC-based NIC matching
#
# Voordelen vs networking.interfaces:
#   - Werkt ongeacht de interface naam (eno1, enp3s0, eth0, ...)
#   - NixOS Wiki 2025 aanbevolen aanpak
#   - Interface naam hoeft NIET bekend te zijn voor deploy
#
# Gebruik in hosts/<node>/default.nix:
#   homelab.node.mac = "aa:bb:cc:dd:ee:ff";  # na hardware discovery
#   homelab.node.ip  = "10.0.20.11/24";
# ---------------------------------------------------------------------------

{
  options.homelab.node = {
    mac = lib.mkOption {
      type        = lib.types.str;
      default     = "TODO_REPLACE_WITH_MAC";
      description = ''
        MAC adres van de primaire NIC.
        Invullen na hardware discovery:
          ip link show | grep -A1 "state UP" | grep "link/ether" | awk "{print \$2}"
        Of via collect-hardware-info.sh of smart-deploy.sh.
      '';
      example = "aa:bb:cc:dd:ee:ff";
    };

    ip = lib.mkOption {
      type        = lib.types.str;
      description = "Statisch IP adres met prefix lengte (CIDR notatie).";
      example     = "10.0.20.11/24";
    };

    disk = lib.mkOption {
      type        = lib.types.str;
      default     = "TODO_REPLACE_WITH_DISK";
      description = ''
        Primaire disk device path.
        HP EliteDesk 800 G4 NVMe  → /dev/nvme0n1
        HP EliteDesk 800 G4 SATA  → /dev/sda
        Invullen na hardware discovery:
          lsblk -dpno NAME,SIZE | grep -v 'loop\|sr' | sort -k2 -hr | head -1
        Of via smart-deploy.sh (automatisch).
      '';
      example = "/dev/nvme0n1";
    };
  };

  config = {
    # systemd-networkd vervangt scripted networking
    networking.useNetworkd = true;
    networking.useDHCP     = false;
    systemd.network.enable = true;

    # Match primaire NIC op MAC adres — werkt op elke hardware
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
        DNS          = [ "1.1.1.1" "8.8.8.8" ];
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
      linkConfig.RequiredForOnline = "routable";
    };
  };
}
