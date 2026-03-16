{ ... }:

# ---------------------------------------------------------------------------
# disko declarative disk layout — applied to all 3 K3s nodes
#
# Assumes a single NVMe/SSD disk. disko wipes and partitions it during
# nixos-anywhere first deploy. Layout:
#
#   /dev/sda1  →  512 MiB  ESP (vfat)    → mounted at /boot
#   /dev/sda2  →  rest      LVM PV
#     homelab-vg/root  →  80 GiB  ext4  → mounted at /
#     homelab-vg/var   →  rest         → mounted at /var
#                                         (Longhorn data lives under /var/lib/longhorn)
#
# Why LVM?
#   Longhorn recommends a dedicated volume for /var/lib/longhorn to avoid
#   filling the root fs. With LVM you can resize online if needed.
#
# IMPORTANT: Change "sda" to match actual disk name on your hardware.
#   HP EliteDesk 800 G4 NVMe → usually "nvme0n1"
#   HP EliteDesk 800 G4 SATA SSD → usually "sda"
#   Check with: lsblk  (run nixos-anywhere with --dry-run first)
# ---------------------------------------------------------------------------

{
  disko.devices = {
    disk = {
      main = {
        type   = "disk";
        device = "/dev/sda";   # ← CHANGE THIS to match your hardware

        content = {
          type = "gpt";

          partitions = {

            # EFI System Partition
            ESP = {
              size     = "512M";
              type     = "EF00";   # EFI partition GUID
              content  = {
                type   = "filesystem";
                format = "vfat";
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

    # ---------------------------------------------------------------------------
    # LVM Volume Group
    # ---------------------------------------------------------------------------
    lvm_vg = {
      homelab-vg = {
        type = "lvm_vg";

        lvs = {

          # Root filesystem — 80 GiB is enough for NixOS store + K3s images
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
          # Longhorn replica data lives at /var/lib/longhorn
          # containerd image store lives at /var/lib/rancher
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
