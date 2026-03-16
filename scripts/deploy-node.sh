#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# deploy-node.sh — deploy NixOS to a node via nixos-anywhere
#
# Usage:
#   nix develop
#   bash scripts/deploy-node.sh node1   # deploys .#node1 to 10.0.20.11
#   bash scripts/deploy-node.sh node2   # deploys .#node2 to 10.0.20.12
#   bash scripts/deploy-node.sh node3   # deploys .#node3 to 10.0.20.13
#
# Prerequisites:
#   - Node booted from NixOS minimal ISO (or any Linux with SSH)
#   - SSH access as root to the node IP
#   - sops secrets encrypted and committed
#   - flake.lock generated (nix flake update)
#
# IMPORTANT: This WIPES the target disk. Run collect-hardware-info.sh first
# and verify disk-config.nix has the correct device name.
# ---------------------------------------------------------------------------

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

header() { echo -e "\n${BLUE}━━━ $1 ${NC}"; }
ok()     { echo -e "${GREEN}  ✓ $1${NC}"; }
warn()   { echo -e "${YELLOW}  ⚠ $1${NC}"; }
die()    { echo -e "${RED}  ✗ $1${NC}"; exit 1; }

NODE="${1:-}"
[[ -z "${NODE}" ]] && die "Usage: $0 <node1|node2|node3>"

# Map node name to IP
case "${NODE}" in
    node1) TARGET_IP="10.0.20.11" ;;
    node2) TARGET_IP="10.0.20.12" ;;
    node3) TARGET_IP="10.0.20.13" ;;
    *)     die "Unknown node: ${NODE}. Use node1, node2, or node3" ;;
esac

header "Deploying ${NODE} → ${TARGET_IP}"
warn "This will WIPE the disk on ${TARGET_IP}!"
echo ""
read -rp "  Type 'yes' to confirm: " CONFIRM
[[ "${CONFIRM}" == "yes" ]] || die "Aborted."

# ---------------------------------------------------------------------------
header "Preflight checks"
# ---------------------------------------------------------------------------
command -v nixos-anywhere &>/dev/null || die "nixos-anywhere not found — run: nix develop"
command -v ssh &>/dev/null            || die "ssh not found"

# Check SSH connectivity
echo "  Testing SSH to root@${TARGET_IP}..."
ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@${TARGET_IP}" 'echo ok' &>/dev/null \
    || die "Cannot SSH to root@${TARGET_IP} — is the node booted and SSH running?"
ok "SSH connection OK"

# Check flake.lock exists
[[ -f flake.lock ]] || die "flake.lock missing — run: nix flake update"
ok "flake.lock present"

# Check secrets are encrypted
if [[ -f secrets/secrets.yaml ]]; then
    if ! grep -q 'ENC\[AES256_GCM' secrets/secrets.yaml && \
       ! grep -q '^sops:' secrets/secrets.yaml; then
        die "secrets/secrets.yaml is NOT encrypted — run: sops secrets/secrets.yaml"
    fi
    ok "secrets.yaml is encrypted"
fi

# ---------------------------------------------------------------------------
header "Deploying via nixos-anywhere"
# ---------------------------------------------------------------------------
echo "  Running: nixos-anywhere --flake .#${NODE} root@${TARGET_IP}"
echo ""

nixos-anywhere \
    --flake ".#${NODE}" \
    --target-host "root@${TARGET_IP}" \
    --extra-files <(
        # Inject the sops age key so the node can decrypt secrets on first boot
        # The key must already exist at ~/.config/sops/age/keys.txt
        AGE_KEY_FILE="${HOME}/.config/sops/age/keys.txt"
        if [[ -f "${AGE_KEY_FILE}" ]]; then
            TMP=$(mktemp -d)
            mkdir -p "${TMP}/var/lib/sops-nix"
            cp "${AGE_KEY_FILE}" "${TMP}/var/lib/sops-nix/key.txt"
            echo "${TMP}"
        else
            warn "No age key found at ${AGE_KEY_FILE} — node won't be able to decrypt secrets"
            echo ""
        fi
    )

ok "nixos-anywhere deploy complete for ${NODE}"

# ---------------------------------------------------------------------------
header "Post-deploy"
# ---------------------------------------------------------------------------
echo "  Node will reboot. Wait ~30s, then verify:"
echo ""
echo "  ssh root@${TARGET_IP} 'systemctl status k3s'"
echo ""

if [[ "${NODE}" == "node1" ]]; then
    warn "node1 is the cluster-init node. After it's up:"
    echo "  1. Wait for K3s to initialize (~60s)"
    echo "  2. Then deploy node2: bash scripts/deploy-node.sh node2"
    echo "  3. Then deploy node3: bash scripts/deploy-node.sh node3"
    echo "  4. Verify cluster: ssh root@10.0.20.11 'k3s kubectl get nodes'"
fi
