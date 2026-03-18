{ config, lib, ... }:

# ---------------------------------------------------------------------------
# disko declarative disk layout — applied to all K3s nodes
#
# Layout:
#   <disk>1  →  512 MiB  ESP (vfat)   → /boot
#   <disk>2  →  rest     LVM PV
#     homelab-vg/root  →  80 GiB ext4  → /
#     homelab-vg/var   →  rest  ext4   → /var  (Longhorn + containerd data)
#
# Disk is set per-host via homelab.node.disk option (auto-detected by smart-deploy.sh):
#   homelab.node.disk = "/dev/nvme0n1";  # NVMe
#   homelab.node.disk = "/dev/sda";      # SATA SSD
# ---------------------------------------------------------------------------

{
  disko.devices = {
    disk = {
      main = {
        type   = "disk";
        device = config.homelab.node.disk;

        content = {
          type = "gpt";

          partitions = {

            # EFI System Partition
            ESP = {
              size    = "512M";
              type    = "EF00";
              content = {
                type       = "filesystem";
                format     = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };

            # LVM Physical Volume — takes all remaining space
            lvm = {
              size    = "100%";
              content = {
                type = "lvm_pv";
                vg   = "homelab-vg";
              };
            };

          };
        };
      };
    };

    lvm_vg = {
      homelab-vg = {
        type = "lvm_vg";

        lvs = {

          # Root filesystem — 80 GiB sufficient for NixOS store + K3s images
          root = {
            size    = "80G";
            content = {
              type       = "filesystem";
              format     = "ext4";
              mountpoint = "/";
              mountOptions = [ "defaults" "noatime" ];
            };
          };

          # /var — remainder of disk
          # Longhorn replicas: /var/lib/longhorn
          # containerd images: /var/lib/rancher
          var = {
            size    = "100%FREE";
            content = {
              type       = "filesystem";
              format     = "ext4";
              mountpoint = "/var";
              mountOptions = [ "defaults" "noatime" ];
            };
          };

        };
      };
    };
  };
}
