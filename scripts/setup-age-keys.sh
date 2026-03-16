#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# setup-age-keys.sh
#
# Run ONCE on your workstation to set up age encryption for sops-nix.
# Requires: age (nix develop will provide it)
#
# Usage:
#   nix develop   # enters the devshell with all tools
#   bash scripts/setup-age-keys.sh
# ---------------------------------------------------------------------------

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

header() { echo -e "\n${BLUE}━━━ $1 ${NC}"; }
ok()     { echo -e "${GREEN}  ✓ $1${NC}"; }
warn()   { echo -e "${YELLOW}  ⚠ $1${NC}"; }

KEY_DIR="${HOME}/.config/sops/age"
KEY_FILE="${KEY_DIR}/keys.txt"

header "Step 1 — Workstation age key"

if [[ -f "${KEY_FILE}" ]]; then
    warn "Key already exists at ${KEY_FILE}"
    WORKSTATION_PUBKEY=$(age-keygen -y "${KEY_FILE}")
    ok "Existing pubkey: ${WORKSTATION_PUBKEY}"
else
    mkdir -p "${KEY_DIR}"
    age-keygen -o "${KEY_FILE}"
    chmod 600 "${KEY_FILE}"
    WORKSTATION_PUBKEY=$(age-keygen -y "${KEY_FILE}")
    ok "Generated new key at ${KEY_FILE}"
    ok "Pubkey: ${WORKSTATION_PUBKEY}"
fi

header "Step 2 — Update .sops.yaml"

echo ""
echo "  Copy the pubkey below into .sops.yaml under '# workstation':"
echo ""
echo "  - ${WORKSTATION_PUBKEY}  # workstation"
echo ""
warn "After all 3 nodes are deployed, get their host age keys with:"
echo ""
echo "  # On node1 (after nixos-anywhere deploy):"
echo "  ssh root@10.0.20.11 'ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'"
echo ""
echo "  # On node2:"
echo "  ssh root@10.0.20.12 'ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'"
echo ""
echo "  # On node3:"
echo "  ssh root@10.0.20.13 'ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'"
echo ""

header "Step 3 — Create and encrypt secrets.yaml"

echo "  After filling .sops.yaml with all pubkeys, run:"
echo ""
echo "  sops secrets/secrets.yaml"
echo ""
echo "  Fill in all the TODO values, save and exit."
echo "  sops will encrypt the file automatically on save."
echo ""

header "Step 4 — Generate flake.lock"

echo "  Run once to pin all nix input versions:"
echo ""
echo "  nix flake update"
echo ""

ok "Done! Next: fill in .sops.yaml pubkeys, then run 'sops secrets/secrets.yaml'"
