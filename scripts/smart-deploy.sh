#!/usr/bin/env bash
# =============================================================================
# smart-deploy.sh — Fully automated NixOS node provisioning
#
# Usage:
#   bash scripts/smart-deploy.sh <temp-ip> <node-name> <role> [--dry-run]
#
# Arguments:
#   temp-ip    Temporary IP (DHCP or USB installer) to reach the machine
#   node-name  NixOS config name: node1 | node2 | ... | node9
#   role       server-init | server-join | worker
#
# Examples:
#   bash scripts/smart-deploy.sh 192.168.1.50 node1 server-init
#   bash scripts/smart-deploy.sh 192.168.1.51 node2 server-join
#   bash scripts/smart-deploy.sh 192.168.1.52 node7 worker
#
# What this script does:
#   1. Connects via SSH to discover MAC address and disk device
#   2. Patches hosts/<node>/default.nix with real MAC + disk (if needed)
#   3. Pre-generates SSH host key, converts to age key
#   4. Adds node age key to .sops.yaml and re-encrypts secrets
#   5. Commits changes to git
#   6. Runs nixos-anywhere to install NixOS
#   7. Waits for node to come up on its static IP
#   8. Verifies K3s joined the cluster
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_IP="${1:-}"
NODE_NAME="${2:-}"
ROLE="${3:-}"
DRY_RUN="${4:-}"

# --- Colours -----------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# --- Validate args -----------------------------------------------------------
[[ -z "$TEMP_IP"   ]] && error "Usage: $0 <temp-ip> <node-name> <role> [--dry-run]"
[[ -z "$NODE_NAME" ]] && error "Usage: $0 <temp-ip> <node-name> <role> [--dry-run]"
[[ -z "$ROLE"      ]] && error "Usage: $0 <temp-ip> <node-name> <role> [--dry-run]"

HOST_FILE="$REPO_ROOT/hosts/$NODE_NAME/default.nix"
[[ -f "$HOST_FILE" ]] || error "Host file not found: $HOST_FILE"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

# =============================================================================
# STEP 1 — Hardware discovery
# =============================================================================
info "==> Step 1: Hardware discovery on $TEMP_IP"

MAC=$(ssh $SSH_OPTS root@"$TEMP_IP" \
  "ip link show | grep -A1 'state UP' | grep 'link/ether' | awk '{print \$2}' | head -1")
[[ -z "$MAC" ]] && error "Could not detect MAC address on $TEMP_IP"
info "Detected MAC: $MAC"

DISK=$(ssh $SSH_OPTS root@"$TEMP_IP" \
  "lsblk -dpno NAME,SIZE | grep -v 'loop\|sr' | sort -k2 -hr | head -1 | awk '{print \$1}'")
[[ -z "$DISK" ]] && error "Could not detect primary disk on $TEMP_IP"
info "Detected primary disk: $DISK"

# =============================================================================
# STEP 2 — Patch host config with real MAC + disk
# =============================================================================
info "==> Step 2: Patching $HOST_FILE"

CURRENT_MAC=$(grep 'mac =' "$HOST_FILE" | grep -o '"[^"]*"' | tr -d '"' | head -1)
CURRENT_DISK=$(grep 'disk =' "$HOST_FILE" | grep -o '"[^"]*"' | tr -d '"' | head -1)

if [[ "$CURRENT_MAC" == "TODO_REPLACE_WITH_MAC" ]]; then
  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    info "[dry-run] Would set mac = \"$MAC\" in $HOST_FILE"
  else
    sed -i "s/mac = \"TODO_REPLACE_WITH_MAC\"/mac = \"$MAC\"/" "$HOST_FILE"
    info "Set mac = \"$MAC\""
  fi
else
  info "MAC already set to $CURRENT_MAC — skipping"
fi

if [[ "$CURRENT_DISK" == "TODO_REPLACE_WITH_DISK" ]]; then
  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    info "[dry-run] Would set disk = \"$DISK\" in $HOST_FILE"
  else
    sed -i "s|disk = \"TODO_REPLACE_WITH_DISK\"|disk = \"$DISK\"|" "$HOST_FILE"
    info "Set disk = \"$DISK\""
  fi
else
  info "Disk already set to $CURRENT_DISK — skipping"
fi

# =============================================================================
# STEP 3 — Pre-generate SSH host key + age key
# =============================================================================
info "==> Step 3: Generating SSH host key for $NODE_NAME"

KEY_DIR="$REPO_ROOT/.ssh-host-keys/$NODE_NAME"
mkdir -p "$KEY_DIR"

if [[ -f "$KEY_DIR/ssh_host_ed25519_key" ]]; then
  warn "SSH host key already exists at $KEY_DIR — reusing"
else
  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    info "[dry-run] Would generate SSH host key at $KEY_DIR"
  else
    ssh-keygen -t ed25519 -N "" -f "$KEY_DIR/ssh_host_ed25519_key" -C "$NODE_NAME"
    info "Generated SSH host key"
  fi
fi

if [[ "$DRY_RUN" != "--dry-run" ]]; then
  AGE_KEY=$(ssh-to-age -i "$KEY_DIR/ssh_host_ed25519_key.pub")
  info "Derived age key: $AGE_KEY"

  # =============================================================================
  # STEP 4 — Add age key to .sops.yaml and re-encrypt secrets
  # =============================================================================
  info "==> Step 4: Adding $NODE_NAME age key to .sops.yaml"

  SOPS_FILE="$REPO_ROOT/.sops.yaml"
  # Insert node key after the workstation key line (only if not already there)
  if grep -q "$AGE_KEY" "$SOPS_FILE"; then
    info "Age key already in .sops.yaml — skipping"
  else
    sed -i "/&workstation/a\\  - &$NODE_NAME $AGE_KEY" "$SOPS_FILE"
    # Add node key as recipient in both creation rules
    sed -i "/\*workstation/a\\              - *$NODE_NAME" "$SOPS_FILE"
    info "Added $NODE_NAME to .sops.yaml"
    info "Re-encrypting secrets (all secret files)..."
    sops updatekeys "$REPO_ROOT/secrets/secrets.yaml"
    for app_secret in "$REPO_ROOT"/apps/*/manifests/secret.yaml; do
      [[ -f "$app_secret" ]] && sops updatekeys "$app_secret"
    done
    info "All secrets re-encrypted"
  fi
fi

# =============================================================================
# STEP 5 — Commit changes
# =============================================================================
info "==> Step 5: Committing changes"

if [[ "$DRY_RUN" == "--dry-run" ]]; then
  info "[dry-run] Would commit: feat: add hardware config for $NODE_NAME"
else
  cd "$REPO_ROOT"
  git add "hosts/$NODE_NAME/default.nix" ".sops.yaml" "secrets/" "apps/" || true
  if ! git diff --cached --quiet; then
    git commit -m "feat: add hardware config for $NODE_NAME ($MAC, $DISK)"
    info "Committed changes"
  else
    info "Nothing to commit"
  fi
fi

# =============================================================================
# STEP 6 — Deploy with nixos-anywhere
# =============================================================================
info "==> Step 6: Deploying NixOS to $NODE_NAME via nixos-anywhere"

EXTRA_FILES_DIR=$(mktemp -d)
if [[ "$DRY_RUN" != "--dry-run" ]] && [[ -f "$KEY_DIR/ssh_host_ed25519_key" ]]; then
  mkdir -p "$EXTRA_FILES_DIR/etc/ssh"
  cp "$KEY_DIR/ssh_host_ed25519_key"     "$EXTRA_FILES_DIR/etc/ssh/"
  cp "$KEY_DIR/ssh_host_ed25519_key.pub" "$EXTRA_FILES_DIR/etc/ssh/"
  chmod 600 "$EXTRA_FILES_DIR/etc/ssh/ssh_host_ed25519_key"
fi

DEPLOY_CMD="nixos-anywhere --flake \"$REPO_ROOT#$NODE_NAME\" root@$TEMP_IP"
if [[ -d "$EXTRA_FILES_DIR/etc" ]]; then
  DEPLOY_CMD="$DEPLOY_CMD --extra-files $EXTRA_FILES_DIR"
fi

if [[ "$DRY_RUN" == "--dry-run" ]]; then
  info "[dry-run] Would run: $DEPLOY_CMD"
else
  eval "$DEPLOY_CMD"
  info "nixos-anywhere deploy complete"
fi

# =============================================================================
# STEP 7 — Wait for node to come up on static IP
# =============================================================================
# Derive static IP from host file
STATIC_IP=$(grep 'ip  =' "$HOST_FILE" | grep -o '"[^"]*"' | tr -d '"' | cut -d'/' -f1)

info "==> Step 7: Waiting for $NODE_NAME to come up at $STATIC_IP"

if [[ "$DRY_RUN" == "--dry-run" ]]; then
  info "[dry-run] Would wait for SSH at $STATIC_IP"
else
  WAIT=0
  until ssh $SSH_OPTS root@"$STATIC_IP" true 2>/dev/null; do
    WAIT=$((WAIT + 5))
    if [[ $WAIT -ge 300 ]]; then
      error "Timeout: $NODE_NAME did not come up at $STATIC_IP within 5 minutes"
    fi
    info "Waiting... ($WAIT s)"
    sleep 5
  done
  info "$NODE_NAME is up at $STATIC_IP"
fi

# =============================================================================
# STEP 8 — Verify K3s cluster membership
# =============================================================================
info "==> Step 8: Verifying K3s cluster membership"

if [[ "$DRY_RUN" == "--dry-run" ]]; then
  info "[dry-run] Would run: kubectl get nodes"
elif [[ "$ROLE" == "server-init" ]]; then
  info "node1 (server-init) — cluster will be ready when K3s starts"
  info "Check: kubectl get nodes --kubeconfig /etc/rancher/k3s/k3s.yaml"
else
  sleep 30  # Give K3s time to register
  NODES=$(ssh $SSH_OPTS root@10.0.20.11 "kubectl get nodes --no-headers 2>/dev/null | grep '$NODE_NAME'" || true)
  if echo "$NODES" | grep -q "$NODE_NAME"; then
    info "SUCCESS: $NODE_NAME is registered in the cluster"
    echo "$NODES"
  else
    warn "$NODE_NAME not yet visible in cluster — it may still be joining"
    warn "Check: ssh root@10.0.20.11 kubectl get nodes"
  fi
fi

# Cleanup
rm -rf "$EXTRA_FILES_DIR"

echo ""
info "=== Deploy complete: $NODE_NAME ($ROLE) ==="
[[ "$ROLE" != "server-init" ]] && info "Next: verify with 'kubectl get nodes' on node1"
