#!/usr/bin/env bash
# =============================================================================
# upgrade-cluster.sh — Rolling NixOS upgrade with automatic rollback
#
# Usage:
#   bash scripts/upgrade-cluster.sh [--dry-run]
#
# What this does:
#   1. Updates flake.lock (pulls latest nixos-25.05)
#   2. Runs nix flake check
#   3. Upgrades nodes one at a time: node1 → node2 → node3 (then node4-9)
#   4. Verifies node health after each upgrade
#   5. On failure: rolls back the failed node and stops
#
# K3s token immutability note:
#   K3s stores its token in /etc/rancher/k3s/k3s.yaml. This token cannot
#   be changed while the cluster is running. Never change k3s.token in
#   secrets.yaml after initial cluster bootstrap.
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN="${1:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=15 -o BatchMode=yes"

# Node IPs — order matters (node1 last = etcd leader goes last)
declare -A NODE_IPS=(
  [node1]="10.0.20.11"
  [node2]="10.0.20.12"
  [node3]="10.0.20.13"
  [node4]="10.0.20.14"
  [node5]="10.0.20.15"
  [node6]="10.0.20.16"
  [node7]="10.0.20.17"
  [node8]="10.0.20.18"
  [node9]="10.0.20.19"
)

# Upgrade order: workers first, then control-plane, etcd leader last
UPGRADE_ORDER=(node7 node8 node9 node2 node3 node4 node5 node6 node1)

wait_for_node() {
  local node="$1" ip="${NODE_IPS[$1]:-}"
  [[ -z "$ip" ]] && return 0  # Skip unconfigured nodes
  local wait=0
  until ssh $SSH_OPTS root@"$ip" true 2>/dev/null; do
    wait=$((wait + 5))
    [[ $wait -ge 180 ]] && { error "Timeout waiting for $node at $ip"; return 1; }
    info "Waiting for $node to come back... ($wait s)"
    sleep 5
  done
  info "$node is back online"
}

node_is_ready() {
  local node="$1"
  ssh $SSH_OPTS root@10.0.20.11 \
    "kubectl get node $node --no-headers 2>/dev/null | grep -q 'Ready'" 2>/dev/null
}

rollback_node() {
  local node="$1" ip="${NODE_IPS[$1]:-}"
  [[ -z "$ip" ]] && return
  warn "Rolling back $node..."
  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    info "[dry-run] Would run: nixos-rebuild switch --rollback on $node"
  else
    ssh $SSH_OPTS root@"$ip" "nixos-rebuild switch --rollback" || \
      error "Rollback failed on $node — manual intervention required"
    wait_for_node "$node"
  fi
}

upgrade_node() {
  local node="$1" ip="${NODE_IPS[$1]:-}"
  [[ -z "$ip" ]] && { info "Skipping $node (no IP configured)"; return 0; }

  # Check if node is reachable
  if ! ssh $SSH_OPTS root@"$ip" true 2>/dev/null; then
    warn "Skipping $node at $ip — not reachable"
    return 0
  fi

  info "==> Upgrading $node ($ip)"

  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    info "[dry-run] Would run: nixos-rebuild switch --flake .#$node --target-host root@$ip"
    return 0
  fi

  # Upgrade
  if ! nixos-rebuild switch --flake "$REPO_ROOT#$node" --target-host "root@$ip"; then
    error "Upgrade failed on $node"
    rollback_node "$node"
    return 1
  fi

  # Wait for node to come back
  wait_for_node "$node"

  # Verify node is Ready in cluster
  sleep 10
  if node_is_ready "$node"; then
    info "$node is Ready in cluster"
  else
    warn "$node not Ready after upgrade — rolling back"
    rollback_node "$node"
    return 1
  fi

  info "$node upgraded successfully"
}

# =============================================================================
# MAIN
# =============================================================================

echo "=== K3s Cluster Rolling Upgrade — $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
[[ "$DRY_RUN" == "--dry-run" ]] && warn "DRY RUN mode — no changes will be made"
echo ""

# Step 1: Update flake inputs
info "==> Step 1: Updating flake.lock"
if [[ "$DRY_RUN" == "--dry-run" ]]; then
  info "[dry-run] Would run: nix flake update"
else
  cd "$REPO_ROOT"
  nix flake update
  info "flake.lock updated"
fi

# Step 2: Validate
info "==> Step 2: Running nix flake check"
if [[ "$DRY_RUN" == "--dry-run" ]]; then
  info "[dry-run] Would run: nix flake check"
else
  nix flake check || { error "nix flake check failed — aborting upgrade"; exit 1; }
  info "flake check passed"
fi

# Step 3: Commit updated lockfile
if [[ "$DRY_RUN" != "--dry-run" ]]; then
  cd "$REPO_ROOT"
  if ! git diff --quiet flake.lock; then
    git add flake.lock
    git commit -m "chore: update flake inputs"
    info "Committed updated flake.lock"
  fi
fi

# Step 4: Rolling upgrade
info "==> Step 3: Rolling upgrade (order: workers → control-plane → etcd leader)"
echo ""

FAILED_NODE=""
for node in "${UPGRADE_ORDER[@]}"; do
  if ! upgrade_node "$node"; then
    FAILED_NODE="$node"
    break
  fi
  echo ""
done

# Final status
echo "=== Upgrade Summary ==="
if [[ -z "$FAILED_NODE" ]]; then
  info "All nodes upgraded successfully"
  bash "$REPO_ROOT/scripts/health-check.sh"
else
  error "Upgrade failed at $FAILED_NODE — cluster may be in mixed state"
  error "Check 'kubectl get nodes' and run 'bash scripts/health-check.sh'"
  exit 1
fi
