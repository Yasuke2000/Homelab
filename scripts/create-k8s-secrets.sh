#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# create-k8s-secrets.sh — create all Kubernetes Secret resources from
# the sops-encrypted secrets/secrets.yaml.
#
# Run this once after the K3s cluster is up, before bootstrapping ArgoCD.
# ArgoCD will then find the secrets already in place when deploying apps.
#
# Prerequisites:
#   - kubectl configured and pointing at your cluster
#   - sops installed and your age key available (~/.config/sops/age/keys.txt)
#   - secrets/secrets.yaml is encrypted (contains ENC[AES256_GCM...])
#
# Usage:
#   bash scripts/create-k8s-secrets.sh
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_FILE="$REPO_ROOT/secrets/secrets.yaml"

if [ ! -f "$SECRETS_FILE" ]; then
  echo "ERROR: $SECRETS_FILE not found"
  exit 1
fi

echo "Decrypting secrets/secrets.yaml with sops..."
SECRETS=$(sops --decrypt "$SECRETS_FILE")

# Helper to extract a value from the decrypted YAML
get() {
  echo "$SECRETS" | yq e ".$1" -
}

echo "Creating namespaces..."
for ns in cert-manager ghost pelican romm shelf silverbullet vaultwarden; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

echo "Creating ghost-secrets..."
kubectl create secret generic ghost-secrets \
  --namespace ghost \
  --from-literal=dbPassword="$(get 'ghost.dbPassword')" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Creating pelican-secrets..."
kubectl create secret generic pelican-secrets \
  --namespace pelican \
  --from-literal=dbPassword="$(get 'pelican.dbPassword')" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Creating romm-secrets..."
kubectl create secret generic romm-secrets \
  --namespace romm \
  --from-literal=dbPassword="$(get 'romm.dbPassword')" \
  --from-literal=secretKey="$(get 'romm.secretKey')" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Creating shelf-secrets..."
kubectl create secret generic shelf-secrets \
  --namespace shelf \
  --from-literal=sessionSecret="$(get 'shelf.sessionSecret')" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Creating silverbullet-secrets..."
kubectl create secret generic silverbullet-secrets \
  --namespace silverbullet \
  --from-literal=password="$(get 'silverbullet.password')" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Creating vaultwarden-secrets..."
kubectl create secret generic vaultwarden-secrets \
  --namespace vaultwarden \
  --from-literal=adminToken="$(get 'vaultwarden.adminToken')" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Creating cloudflare-api-token (cert-manager DNS-01)..."
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token="$(get 'cloudflare.apiToken')" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "All Kubernetes secrets created successfully."
echo "Verify with: kubectl get secrets -A | grep -E 'ghost|pelican|romm|shelf|silverbullet|vaultwarden|cloudflare'"
