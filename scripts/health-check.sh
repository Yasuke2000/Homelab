#!/usr/bin/env bash
# =============================================================================
# health-check.sh — K3s cluster health monitoring
#
# Usage:
#   bash scripts/health-check.sh [--full]
#
# Without --full: quick node/pod status
# With    --full: also checks etcd, storage, and ArgoCD
# =============================================================================

set -euo pipefail

CONTROL_PLANE="root@10.0.20.11"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
FULL="${1:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; FAILED=1; }
FAILED=0

remote() { ssh $SSH_OPTS "$CONTROL_PLANE" "$@"; }

echo "=== K3s Cluster Health Check — $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
echo ""

# --- Nodes -------------------------------------------------------------------
echo "--- Nodes ---"
NODE_STATUS=$(remote "kubectl get nodes --no-headers 2>/dev/null" || echo "ERROR")
if [[ "$NODE_STATUS" == "ERROR" ]]; then
  fail "Cannot reach kubectl on node1 — is K3s running?"
else
  echo "$NODE_STATUS"
  NOT_READY=$(echo "$NODE_STATUS" | grep -v " Ready" | grep -v "^$" || true)
  if [[ -z "$NOT_READY" ]]; then
    ok "All nodes Ready"
  else
    fail "Some nodes not Ready:"
    echo "$NOT_READY"
  fi
fi
echo ""

# --- System pods -------------------------------------------------------------
echo "--- System pods (kube-system) ---"
POD_STATUS=$(remote "kubectl get pods -n kube-system --no-headers 2>/dev/null" || echo "ERROR")
if [[ "$POD_STATUS" == "ERROR" ]]; then
  fail "Cannot list pods"
else
  UNHEALTHY=$(echo "$POD_STATUS" | grep -v "Running\|Completed" | grep -v "^$" || true)
  if [[ -z "$UNHEALTHY" ]]; then
    ok "All kube-system pods healthy"
  else
    fail "Unhealthy pods in kube-system:"
    echo "$UNHEALTHY"
  fi
fi
echo ""

# --- MetalLB -----------------------------------------------------------------
echo "--- MetalLB ---"
MLB_PODS=$(remote "kubectl get pods -n metallb-system --no-headers 2>/dev/null" || echo "ERROR")
if [[ "$MLB_PODS" == "ERROR" ]] || [[ -z "$MLB_PODS" ]]; then
  warn "MetalLB not deployed yet"
else
  MLB_BAD=$(echo "$MLB_PODS" | grep -v "Running" | grep -v "^$" || true)
  [[ -z "$MLB_BAD" ]] && ok "MetalLB healthy" || fail "MetalLB issues: $MLB_BAD"
fi
echo ""

# --- Traefik -----------------------------------------------------------------
echo "--- Traefik ---"
TR_PODS=$(remote "kubectl get pods -n traefik --no-headers 2>/dev/null" || echo "ERROR")
if [[ "$TR_PODS" == "ERROR" ]] || [[ -z "$TR_PODS" ]]; then
  warn "Traefik not deployed yet"
else
  TR_BAD=$(echo "$TR_PODS" | grep -v "Running" | grep -v "^$" || true)
  [[ -z "$TR_BAD" ]] && ok "Traefik healthy" || fail "Traefik issues: $TR_BAD"
fi
echo ""

# --- ArgoCD ------------------------------------------------------------------
echo "--- ArgoCD ---"
ARGO_PODS=$(remote "kubectl get pods -n argocd --no-headers 2>/dev/null" || echo "ERROR")
if [[ "$ARGO_PODS" == "ERROR" ]] || [[ -z "$ARGO_PODS" ]]; then
  warn "ArgoCD not deployed yet"
else
  ARGO_BAD=$(echo "$ARGO_PODS" | grep -v "Running\|Completed" | grep -v "^$" || true)
  [[ -z "$ARGO_BAD" ]] && ok "ArgoCD healthy" || fail "ArgoCD issues: $ARGO_BAD"
fi
echo ""

if [[ "$FULL" == "--full" ]]; then
  # --- etcd ------------------------------------------------------------------
  echo "--- etcd health ---"
  ETCD=$(remote "ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
    --cert=/var/lib/rancher/k3s/server/tls/etcd/server-client.crt \
    --key=/var/lib/rancher/k3s/server/tls/etcd/server-client.key \
    endpoint health --cluster 2>/dev/null" || echo "ERROR")
  if [[ "$ETCD" == "ERROR" ]]; then
    warn "Cannot check etcd (etcdctl not available or K3s not running)"
  else
    echo "$ETCD"
    echo "$ETCD" | grep -q "is healthy" && ok "etcd healthy" || fail "etcd issues detected"
  fi
  echo ""

  # --- Longhorn --------------------------------------------------------------
  echo "--- Longhorn ---"
  LH_PODS=$(remote "kubectl get pods -n longhorn-system --no-headers 2>/dev/null" || echo "ERROR")
  if [[ "$LH_PODS" == "ERROR" ]] || [[ -z "$LH_PODS" ]]; then
    warn "Longhorn not deployed yet"
  else
    LH_BAD=$(echo "$LH_PODS" | grep -v "Running\|Completed" | grep -v "^$" || true)
    [[ -z "$LH_BAD" ]] && ok "Longhorn healthy" || fail "Longhorn issues: $LH_BAD"
  fi
  echo ""

  # --- cert-manager ----------------------------------------------------------
  echo "--- cert-manager ---"
  CM_PODS=$(remote "kubectl get pods -n cert-manager --no-headers 2>/dev/null" || echo "ERROR")
  if [[ "$CM_PODS" == "ERROR" ]] || [[ -z "$CM_PODS" ]]; then
    warn "cert-manager not deployed yet"
  else
    CM_BAD=$(echo "$CM_PODS" | grep -v "Running" | grep -v "^$" || true)
    [[ -z "$CM_BAD" ]] && ok "cert-manager healthy" || fail "cert-manager issues: $CM_BAD"
  fi
  echo ""

  # --- ArgoCD app sync status -----------------------------------------------
  echo "--- ArgoCD app sync status ---"
  ARGO_APPS=$(remote "kubectl get applications -n argocd --no-headers 2>/dev/null" || echo "ERROR")
  if [[ "$ARGO_APPS" == "ERROR" ]] || [[ -z "$ARGO_APPS" ]]; then
    warn "No ArgoCD applications found"
  else
    echo "$ARGO_APPS"
    OUT_OF_SYNC=$(echo "$ARGO_APPS" | grep -v "Synced" | grep -v "^$" || true)
    [[ -z "$OUT_OF_SYNC" ]] && ok "All ArgoCD apps Synced" || warn "Some apps out of sync"
  fi
  echo ""
fi

# --- Summary -----------------------------------------------------------------
echo "=== Summary ==="
if [[ $FAILED -eq 0 ]]; then
  ok "Cluster is healthy"
else
  fail "Cluster has issues — see above"
  exit 1
fi
