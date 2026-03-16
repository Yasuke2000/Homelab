#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# collect-hardware-info.sh
#
# Run this script on each node BEFORE deploying NixOS.
# Boot from a NixOS minimal ISO or Ubuntu live USB, then run:
#
#   curl -sL https://raw.githubusercontent.com/Yasuke2000/Homelab/main/scripts/collect-hardware-info.sh | bash
#   # or if you have the repo cloned:
#   bash scripts/collect-hardware-info.sh
#
# Output: prints everything you need to fill in the TODO fields in the repo.
# Optionally writes to a file: ./node-info-$(hostname).txt
# ---------------------------------------------------------------------------

set -euo pipefail

NODE_NAME="${1:-$(hostname)}"
OUTPUT_FILE="node-info-${NODE_NAME}.txt"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

header() { echo -e "\n${BLUE}━━━ $1 ${NC}"; }
ok()     { echo -e "${GREEN}  ✓ $1${NC}"; }
info()   { echo -e "  $1"; }
warn()   { echo -e "${YELLOW}  ⚠ $1${NC}"; }

{
echo "============================================================"
echo " Homelab Hardware Info — ${NODE_NAME}"
echo " Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "============================================================"

# ---------------------------------------------------------------------------
header "SYSTEM INFO"
# ---------------------------------------------------------------------------
if command -v dmidecode &>/dev/null; then
    PRODUCT=$(dmidecode -s system-product-name 2>/dev/null || echo "unknown")
    MANUFACTURER=$(dmidecode -s system-manufacturer 2>/dev/null || echo "unknown")
    SERIAL=$(dmidecode -s system-serial-number 2>/dev/null || echo "unknown")
    BIOS=$(dmidecode -s bios-version 2>/dev/null || echo "unknown")
    info "Product:      ${MANUFACTURER} ${PRODUCT}"
    info "Serial:       ${SERIAL}"
    info "BIOS version: ${BIOS}"
else
    warn "dmidecode not available — install it or run as root"
    info "Product: $(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)"
fi

# ---------------------------------------------------------------------------
header "CPU"
# ---------------------------------------------------------------------------
CPU_MODEL=$(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
CPU_CORES=$(nproc)
info "Model:  ${CPU_MODEL}"
info "Cores:  ${CPU_CORES}"

# ---------------------------------------------------------------------------
header "MEMORY"
# ---------------------------------------------------------------------------
TOTAL_MEM=$(awk '/MemTotal/ {printf "%.1f GiB", $2/1024/1024}' /proc/meminfo)
info "Total RAM: ${TOTAL_MEM}"

# ---------------------------------------------------------------------------
header "DISKS — copy the device name into modules/disk-config.nix"
# ---------------------------------------------------------------------------
info "lsblk output:"
lsblk -d -o NAME,SIZE,TYPE,ROTA,MODEL,TRAN 2>/dev/null || lsblk -d

echo ""
warn "→ Use the NAME column in modules/disk-config.nix:"
warn "  disko.devices.disk.main.device = \"/dev/NAME\";"
warn "  (NVMe example: /dev/nvme0n1 — SATA SSD example: /dev/sda)"

# ---------------------------------------------------------------------------
header "NETWORK INTERFACES — copy the name into hosts/nodeX/default.nix"
# ---------------------------------------------------------------------------
info "All interfaces:"
ip -o link show | awk '{print "  " $2, $3}' | grep -v 'lo:'

echo ""
info "Interface details (UP only):"
ip -o link show up | while read -r line; do
    IFACE=$(echo "$line" | awk '{print $2}' | tr -d ':')
    [[ "$IFACE" == "lo" ]] && continue

    MAC=$(echo "$line" | grep -o 'link/ether [0-9a-f:]*' | awk '{print $2}')
    STATE=$(echo "$line" | grep -o 'state [A-Z]*' | awk '{print $2}')
    SPEED=""
    if [[ -f "/sys/class/net/${IFACE}/speed" ]]; then
        SPEED=$(cat "/sys/class/net/${IFACE}/speed" 2>/dev/null || echo "?")
        [[ "$SPEED" != "-1" ]] && SPEED="${SPEED} Mbps" || SPEED="unknown"
    fi

    info "  Interface: ${IFACE}"
    info "    MAC:     ${MAC}"
    info "    State:   ${STATE}"
    info "    Speed:   ${SPEED}"
done

echo ""
MAIN_IFACE=$(ip route get 8.8.8.8 2>/dev/null | grep -o 'dev [a-z0-9]*' | awk '{print $2}' || echo "unknown")
warn "→ Main interface (use in networking.interfaces): ${MAIN_IFACE}"
warn "  networking.interfaces.\"${MAIN_IFACE}\" = { ... };"
warn "  services.k3s.extraFlags = \"--flannel-iface=${MAIN_IFACE}\";"

# ---------------------------------------------------------------------------
header "CURRENT IP CONFIG"
# ---------------------------------------------------------------------------
ip -4 addr show | grep -v '127.0.0.1' | grep inet | awk '{print "  " $NF ": " $2}'

GATEWAY=$(ip route | grep default | awk '{print $3}' | head -1)
info "Gateway: ${GATEWAY}"

# ---------------------------------------------------------------------------
header "PCIE / USB DEVICES (GPU, network cards)"
# ---------------------------------------------------------------------------
if command -v lspci &>/dev/null; then
    info "Relevant PCIe devices:"
    lspci | grep -iE 'vga|display|network|ethernet|nvme|storage' | sed 's/^/  /'
else
    warn "lspci not available (install pciutils)"
fi

# ---------------------------------------------------------------------------
header "SSH HOST KEY → age public key for .sops.yaml"
# ---------------------------------------------------------------------------
info "If SSH host keys exist, convert to age for .sops.yaml:"
if [[ -f /etc/ssh/ssh_host_ed25519_key.pub ]]; then
    if command -v ssh-to-age &>/dev/null; then
        AGE_KEY=$(ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub)
        ok "Age pubkey (add to .sops.yaml): ${AGE_KEY}"
    else
        info "  SSH ed25519 pubkey: $(cat /etc/ssh/ssh_host_ed25519_key.pub)"
        warn "  Install ssh-to-age to convert: nix run nixpkgs#ssh-to-age"
        warn "  Or: nix-shell -p ssh-to-age --run 'ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'"
    fi
else
    warn "No SSH host key found — will be generated on first NixOS boot"
    warn "After deploy, run: ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub"
fi

# ---------------------------------------------------------------------------
header "SUMMARY — copy these values into your repo"
# ---------------------------------------------------------------------------
echo ""
echo "  ┌─ hosts/nodeX/default.nix ─────────────────────────────────────"
echo "  │  networking.hostName = \"homelab-nodeX\";"
echo "  │  networking.interfaces.\"${MAIN_IFACE:-eno1}\" = {"
echo "  │    ipv4.addresses = [{ address = \"10.0.20.1X\"; prefixLength = 24; }];"
echo "  │  };"
echo "  └────────────────────────────────────────────────────────────────"
echo ""
echo "  ┌─ modules/disk-config.nix ──────────────────────────────────────"
DISK=$(lsblk -d -o NAME,TYPE | grep disk | head -1 | awk '{print $1}')
echo "  │  disko.devices.disk.main.device = \"/dev/${DISK:-sda}\";"
echo "  └────────────────────────────────────────────────────────────────"
echo ""
echo "  ┌─ modules/k3s-server-*.nix ─────────────────────────────────────"
echo "  │  \"--flannel-iface=${MAIN_IFACE:-eno1}\""
echo "  └────────────────────────────────────────────────────────────────"
echo ""

} | tee "${OUTPUT_FILE}"

echo ""
echo -e "${GREEN}Output saved to: ${OUTPUT_FILE}${NC}"
echo -e "${YELLOW}Share this file with yourself (scp, USB, etc.) then fill in the TODOs.${NC}"
