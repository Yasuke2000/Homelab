# Deployment Guide

Step-by-step guide to bootstrap the cluster from bare metal to fully running.

## What is manual vs automated?

```
YOU do:                              AUTOMATED:
───────────────────────────────────  ────────────────────────────────────────
1. Boot nodes from Ventoy USB    →   NixOS live environment
2. Run smart-deploy.sh per node  →   Hardware discovered (MAC + disk)
                                 →   SSH host key generated
                                 →   Age key derived + added to .sops.yaml
                                 →   Secrets re-encrypted for the node
                                 →   NixOS installed + K3s started
3. Run bootstrap-argocd.sh       →   ArgoCD installed
                                 →   App of Apps synced
                                 →   Kyverno, MetalLB, Traefik, cert-manager,
                                     Longhorn, all apps deployed in order
```

---

## Phase 0 — Workstation setup (once)

```bash
# Clone repo and enter dev shell (provides all tools)
git clone https://github.com/Yasuke2000/Homelab.git
cd Homelab
nix develop
# Now you have: kubectl, helm, sops, age, ssh-to-age, nixos-anywhere, k9s
```

---

## Phase 1 — Provision nodes

Boot each HP EliteDesk from the Ventoy USB (see [Node Provisioning](node-provisioning.md) for USB setup).

Once the NixOS installer is running and you have the DHCP IP, run:

```bash
# Node 1 — bootstraps the etcd cluster (always first)
bash scripts/smart-deploy.sh 192.168.1.50 node1 server-init

# Node 2 — joins the cluster
bash scripts/smart-deploy.sh 192.168.1.51 node2 server-join

# Node 3 — joins the cluster
bash scripts/smart-deploy.sh 192.168.1.52 node3 server-join
```

Each run automatically:

1. SSHes to the temporary IP and detects the MAC address and primary disk
2. Patches `hosts/<node>/default.nix` with real hardware values
3. Generates an SSH host key and derives the node age key
4. Adds the node age key to `.sops.yaml` and re-encrypts all secrets
5. Commits the changes to git
6. Deploys NixOS via nixos-anywhere (wipes disk, fully unattended)
7. Waits for the node to come up on its static IP
8. Verifies K3s cluster membership

Verify after each deploy:

```bash
# Check all nodes are Ready
ssh root@10.0.20.11 kubectl get nodes

# Expected output after all 3:
# NAME             STATUS   ROLES                       AGE
# homelab-node1    Ready    control-plane,etcd,master   5m
# homelab-node2    Ready    control-plane,etcd,master   3m
# homelab-node3    Ready    control-plane,etcd,master   1m
```

---

## Phase 2 — Bootstrap ArgoCD

```bash
# Copy kubeconfig from node1
scp root@10.0.20.11:/etc/rancher/k3s/k3s.yaml ./kubeconfig
sed -i 's/127.0.0.1/10.0.20.11/' kubeconfig
export KUBECONFIG=$(pwd)/kubeconfig

# Bootstrap
bash scripts/bootstrap-argocd.sh
```

ArgoCD then syncs everything automatically in order (sync-waves):

```
wave -5  →  Kyverno installed
wave -4  →  MetalLB + Kyverno Longhorn PATH fix loaded
wave -3  →  Traefik installed → gets IP 10.0.20.100 from MetalLB
wave -2  →  cert-manager installed
wave -1  →  Longhorn installed (works correctly with Kyverno fix in place)
wave  0  →  All apps: Vaultwarden, Jellyfin, Ghost, Silverbullet, ...
```

Monitor progress:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: https://localhost:8080
# Username: admin  |  Password: printed by bootstrap-argocd.sh
```

---

## Phase 3 — TrueNAS NFS setup

Before Longhorn and media apps are fully functional, configure NFS on the TrueNAS node (10.0.20.14):

1. Open TrueNAS web UI at `http://10.0.20.14`
2. Create datasets: `longhorn-backup`, `media`, `roms`
3. Enable NFS shares for each with network `10.0.20.0/24`

---

## Phase 4 — Switch TLS to production

Once all apps are running with staging certificates:

```bash
# Verify staging certs are all issued
kubectl get certificates -A

# Switch everything to production (after verifying staging works)
grep -rl "letsencrypt-staging" apps/ | xargs sed -i 's/letsencrypt-staging/letsencrypt-prod/g'
git add apps/ && git commit -m "feat: switch to letsencrypt-prod" && git push
```

See [Staging to Production](staging-to-prod.md) for the full checklist.

---

## Phase summary

| Phase | You run | Result |
|---|---|---|
| 1a | `smart-deploy.sh <ip> node1 server-init` | NixOS + K3s cluster initialized |
| 1b | `smart-deploy.sh <ip> node2/3 server-join` | HA cluster with 3 nodes |
| 2 | `bootstrap-argocd.sh` | All 11 apps deployed via GitOps |
| 3 | TrueNAS web UI | NFS storage available |
| 4 | One sed + git push | Production TLS everywhere |
