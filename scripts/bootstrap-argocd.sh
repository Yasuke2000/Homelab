#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# bootstrap-argocd.sh
#
# Run ONCE after K3s is up on all 3 nodes.
# Installs ArgoCD and applies the App of Apps to hand everything over to GitOps.
#
# Prerequisites:
#   - K3s running on all 3 nodes
#   - KUBECONFIG set: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
#     (or copy it to your workstation)
#   - kubectl available (nix develop provides it)
#
# Usage:
#   nix develop
#   export KUBECONFIG=/path/to/k3s.yaml
#   bash scripts/bootstrap-argocd.sh
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

# ---------------------------------------------------------------------------
header "Preflight checks"
# ---------------------------------------------------------------------------

command -v kubectl &>/dev/null || die "kubectl not found — run: nix develop"
kubectl cluster-info &>/dev/null   || die "Cannot reach cluster — check KUBECONFIG"

NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || true)
ok "Cluster reachable — ${READY}/${NODES} nodes Ready"

[[ "${READY}" -ge 1 ]] || die "No Ready nodes — wait for K3s to stabilize"

# ---------------------------------------------------------------------------
header "Step 1 — Apply namespaces"
# ---------------------------------------------------------------------------
kubectl apply -f infrastructure/namespaces.yaml
ok "Namespaces created"

# ---------------------------------------------------------------------------
header "Step 2 — Install ArgoCD"
# ---------------------------------------------------------------------------
# CRITICAL: --server-side --force-conflicts required for ArgoCD v3
# See: docs/gotchas.md #4
kubectl apply \
    --server-side \
    --force-conflicts \
    -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

ok "ArgoCD manifest applied"

# ---------------------------------------------------------------------------
header "Step 3 — Wait for ArgoCD to be ready"
# ---------------------------------------------------------------------------
echo "  Waiting for argocd-server..."
kubectl wait deployment argocd-server \
    -n argocd \
    --for=condition=Available \
    --timeout=300s
ok "ArgoCD server ready"

# ---------------------------------------------------------------------------
header "Step 4 — Apply App of Apps"
# ---------------------------------------------------------------------------
kubectl apply -f apps/app-of-apps.yaml
ok "App of Apps applied — ArgoCD will now sync everything"

# ---------------------------------------------------------------------------
header "Step 5 — Get initial admin password"
# ---------------------------------------------------------------------------
echo ""
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)
ok "ArgoCD initial admin password: ${ARGOCD_PASS}"
warn "Change this password immediately after first login!"
echo ""
echo "  Port-forward to access UI locally:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Then open: https://localhost:8080"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASS}"
echo ""

# ---------------------------------------------------------------------------
header "Step 6 — Summary"
# ---------------------------------------------------------------------------
ok "Bootstrap complete!"
echo ""
echo "  ArgoCD will now sync in this order (sync-waves):"
echo "    wave -10  App of Apps"
echo "    wave  -5  Kyverno + ArgoCD self-manage"
echo "    wave  -4  MetalLB + Kyverno Longhorn fix"
echo "    wave  -3  Traefik"
echo "    wave  -2  cert-manager"
echo "    wave  -1  Longhorn"
echo "    wave   0  All apps (Vaultwarden, Jellyfin, etc.)"
echo ""
warn "Monitor sync progress in the ArgoCD UI or with:"
echo "  kubectl get applications -n argocd -w"
