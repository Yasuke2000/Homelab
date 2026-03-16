#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# create-github-issues.sh
#
# Creates all GitHub issues for the homelab setup roadmap.
#
# Prerequisites:
#   gh auth login   (GitHub CLI, install: https://cli.github.com)
#
# Usage:
#   bash scripts/create-github-issues.sh
# ---------------------------------------------------------------------------

set -euo pipefail

REPO="Yasuke2000/Homelab"

echo "Creating GitHub issues for $REPO..."

# ---------------------------------------------------------------------------
gh issue create --repo "$REPO" \
  --title "Phase 1: Collect hardware info from all 3 nodes" \
  --label "setup" \
  --body "## What
Run the hardware collection script on each node while booted from NixOS live ISO.

## Steps
1. Flash NixOS minimal ISO to USB: https://nixos.org/download → Minimal ISO x86_64
2. Boot each HP EliteDesk 800 G4 from USB
3. Set root password on live system: \`passwd root\`
4. Run from your workstation:
\`\`\`bash
ssh root@10.0.20.11 'bash -s' < scripts/collect-hardware-info.sh node1
ssh root@10.0.20.12 'bash -s' < scripts/collect-hardware-info.sh node2
ssh root@10.0.20.13 'bash -s' < scripts/collect-hardware-info.sh node3
\`\`\`

## Files to update based on output
- [ ] \`modules/disk-config.nix\` — replace \`/dev/sda\` with actual disk (e.g. \`nvme0n1\`)
- [ ] \`hosts/node1/default.nix\` — replace \`eno1\` with actual NIC name + add SSH key
- [ ] \`hosts/node2/default.nix\` — replace \`eno1\` with actual NIC name + add SSH key
- [ ] \`hosts/node3/default.nix\` — replace \`eno1\` with actual NIC name + add SSH key
- [ ] \`modules/k3s-server-init.nix\` — replace \`eno1\` in \`--flannel-iface\`
- [ ] \`modules/k3s-server-join.nix\` — replace \`eno1\` in \`--flannel-iface\`"

echo "✓ Issue 1 created"

# ---------------------------------------------------------------------------
gh issue create --repo "$REPO" \
  --title "Phase 2: Setup age encryption keys and encrypt secrets" \
  --label "setup,security" \
  --body "## What
Generate age keys and encrypt \`secrets/secrets.yaml\` with sops.

## Steps
\`\`\`bash
nix develop
bash scripts/setup-age-keys.sh
\`\`\`

Update \`.sops.yaml\` with your workstation age pubkey, then encrypt:
\`\`\`bash
sops secrets/secrets.yaml
\`\`\`

## Values to fill in \`secrets/secrets.yaml\`
- [ ] \`k3s.token\` — \`openssl rand -hex 32\`
- [ ] \`vaultwarden.adminToken\` — \`openssl rand -base64 48\`
- [ ] \`vaultwarden.smtpUsername\` + \`smtpPassword\`
- [ ] \`actualBudget.password\`
- [ ] \`ghost.dbPassword\`
- [ ] \`silverbullet.password\`
- [ ] \`shelf.sessionSecret\` — \`openssl rand -base64 32\`
- [ ] \`romm.dbPassword\` + \`romm.secretKey\`
- [ ] \`pelican.dbPassword\`
- [ ] \`grafana.adminPassword\`
- [ ] \`renovate.githubToken\` — GitHub PAT with repo + read:org

## After node deploy (Phase 3): add node age keys
\`\`\`bash
ssh root@10.0.20.11 'nix-shell -p ssh-to-age --run \"ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub\"'
# repeat for node2 + node3, add to .sops.yaml, then:
sops updatekeys secrets/secrets.yaml
\`\`\`"

echo "✓ Issue 2 created"

# ---------------------------------------------------------------------------
gh issue create --repo "$REPO" \
  --title "Phase 3: Set domain name across all manifests" \
  --label "setup,configuration" \
  --body "## What
Replace all \`yourdomain.com\` placeholders with the real domain.

## Files affected
Tell me your domain and I will do a find-and-replace across the entire repo.

Files with domain TODOs:
- \`apps/argocd/application.yaml\`
- \`apps/traefik/application.yaml\`
- \`apps/longhorn/application.yaml\`
- \`apps/cert-manager/cluster-issuer.yaml\` (also needs real email)
- \`apps/monitoring/application.yaml\`
- \`apps/vaultwarden/manifests/deployment.yaml\`
- \`apps/jellyfin/manifests/deployment.yaml\`
- \`apps/jellyseerr/manifests/deployment.yaml\`
- \`apps/actual-budget/manifests/deployment.yaml\`
- \`apps/ghost/manifests/deployment.yaml\`
- \`apps/silverbullet/manifests/deployment.yaml\`
- \`apps/shelf/manifests/deployment.yaml\`
- \`apps/romm/manifests/deployment.yaml\`
- \`apps/pelican/manifests/deployment.yaml\`
- \`apps/homepage/manifests/configmap.yaml\` (many entries)
- \`apps/homepage/manifests/deployment.yaml\`
- \`apps/monitoring/uptime-kuma-manifests/deployment.yaml\`

## Also needed
- [ ] Email address in \`apps/cert-manager/cluster-issuer.yaml\`
- [ ] Traefik LoadBalancer IP in \`apps/traefik/application.yaml\` (from MetalLB pool)"

echo "✓ Issue 3 created"

# ---------------------------------------------------------------------------
gh issue create --repo "$REPO" \
  --title "Phase 4: Generate flake.lock and deploy NixOS to all nodes" \
  --label "setup,deployment" \
  --body "## Prerequisites
- [ ] Issue 1 complete (hardware info + host configs filled in)
- [ ] Issue 2 complete (secrets encrypted)
- [ ] Issue 3 complete (domain set) — optional, can do after

## Steps
\`\`\`bash
nix develop
nix flake update          # generates flake.lock
git add flake.lock
git commit -m 'chore: add flake.lock'
git push

# Deploy (in order — node1 must be first)
bash scripts/deploy-node.sh node1
# Wait ~60s for K3s to initialize
ssh root@10.0.20.11 'systemctl status k3s'

bash scripts/deploy-node.sh node2
bash scripts/deploy-node.sh node3

# Verify all 3 nodes in cluster
ssh root@10.0.20.11 'k3s kubectl get nodes'
\`\`\`

## Expected result
\`\`\`
NAME             STATUS   ROLES                       AGE
homelab-node1    Ready    control-plane,etcd,master   5m
homelab-node2    Ready    control-plane,etcd,master   2m
homelab-node3    Ready    control-plane,etcd,master   1m
\`\`\`"

echo "✓ Issue 4 created"

# ---------------------------------------------------------------------------
gh issue create --repo "$REPO" \
  --title "Phase 5: Bootstrap ArgoCD and deploy all apps" \
  --label "setup,deployment" \
  --body "## Prerequisites
- [ ] Issue 4 complete (all 3 nodes running K3s)

## Steps
\`\`\`bash
# Get kubeconfig from node1
scp root@10.0.20.11:/etc/rancher/k3s/k3s.yaml ./kubeconfig
sed -i 's/127.0.0.1/10.0.20.11/' kubeconfig
export KUBECONFIG=\$(pwd)/kubeconfig

# Bootstrap
bash scripts/bootstrap-argocd.sh
\`\`\`

## What deploys automatically (sync-waves)
| Wave | What |
|------|------|
| -5 | Kyverno |
| -4 | MetalLB + Kyverno Longhorn fix |
| -3 | Traefik → gets IP from MetalLB |
| -2 | cert-manager |
| -1 | Longhorn |
| 0 | All apps: Vaultwarden, Jellyfin, Ghost, SilverBullet, etc. |

## Monitor progress
\`\`\`bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080
\`\`\`"

echo "✓ Issue 5 created"

# ---------------------------------------------------------------------------
gh issue create --repo "$REPO" \
  --title "TrueNAS: Create NFS shares for cluster storage" \
  --label "configuration,storage" \
  --body "## What
Create NFS shares on TrueNAS SCALE (10.0.20.14) before apps that need them are deployed.

## Required shares
| Path | Used by |
|------|---------|
| \`/mnt/datapool/media\` | Jellyfin (movies, TV, music) |
| \`/mnt/datapool/roms\` | RomM (ROM files) |
| \`/mnt/datapool/longhorn-backup\` | Longhorn backup target |

## Steps in TrueNAS UI
1. Datasets → Add Dataset for each path above
2. Shares → Unix Shares (NFS) → Add
3. Set network: \`10.0.20.0/24\` (allow all VLAN 20 hosts)
4. Maproot User: root

## Recommended NFS mount options (in K8s PVs)
\`\`\`
nfsvers=4.1,hard,intr,rsize=1048576,wsize=1048576,timeo=600
\`\`\`
⚠️ Never use \`soft\` — causes silent data corruption on timeout.

## After creating shares
Update these files with the correct NFS paths:
- [ ] \`apps/longhorn/application.yaml\` — \`backupTarget\` line
- [ ] \`apps/jellyfin/manifests/deployment.yaml\` — NFS volume
- [ ] \`apps/romm/manifests/deployment.yaml\` — NFS volume"

echo "✓ Issue 6 created"

# ---------------------------------------------------------------------------
gh issue create --repo "$REPO" \
  --title "Pin all container image versions (replace :latest tags)" \
  --label "maintenance,security" \
  --body "## What
All container images currently use \`:latest\` which is bad practice.
Renovate will keep them updated, but only if they are pinned to a specific version first.

## Images to pin
- [ ] \`vaultwarden/server:latest\`
- [ ] \`jellyfin/jellyfin:latest\`
- [ ] \`fallenbagel/jellyseerr:latest\`
- [ ] \`actualbudget/actual-server:latest\`
- [ ] \`ghost:5-alpine\`
- [ ] \`mysql:8.0\` (used by ghost + pelican)
- [ ] \`ghcr.io/silverbulletmd/silverbullet:latest\`
- [ ] \`ghcr.io/shelf-nu/shelf.nu:latest\`
- [ ] \`rommapp/romm:latest\`
- [ ] \`mariadb:11\`
- [ ] \`ghcr.io/pelican-dev/panel:latest\`
- [ ] \`ghcr.io/gethomepage/homepage:latest\`
- [ ] \`louislam/uptime-kuma:1\`

## How
Check each image's GitHub/DockerHub for latest release tag, then replace in manifests.
Once pinned, Renovate will automatically create PRs when new versions are released."

echo "✓ Issue 7 created"

# ---------------------------------------------------------------------------
gh issue create --repo "$REPO" \
  --title "Configure Kubernetes Secret resources for apps" \
  --label "security,configuration" \
  --body "## What
The deployment manifests reference Kubernetes Secrets (\`secretKeyRef\`) but the actual
Secret resources are never created. These need to be created from sops-encrypted values.

## Missing secrets per namespace
| Namespace | Secret name | Keys needed |
|-----------|-------------|-------------|
| vaultwarden | \`vaultwarden-secrets\` | adminToken |
| ghost | \`ghost-secrets\` | dbPassword |
| silverbullet | \`silverbullet-secrets\` | password |
| shelf | \`shelf-secrets\` | sessionSecret |
| romm | \`romm-secrets\` | dbPassword, secretKey |
| pelican | \`pelican-secrets\` | dbPassword |
| monitoring | \`grafana-secrets\` | adminPassword |

## Solution
Use External Secrets Operator or sops-nix to inject these as K8s Secrets from the
encrypted \`secrets/secrets.yaml\`.

Simplest approach: add a \`secret.yaml\` to each app's manifests directory that
references the sops-decrypted values, applied via ArgoCD.

This will be handled in a follow-up after the initial deploy is verified."

echo "✓ Issue 8 created"

echo ""
echo "All issues created at: https://github.com/$REPO/issues"
