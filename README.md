# David's Homelab

Sovereign bare-metal NixOS homelab running a K3s HA cluster on HP EliteDesk 800 G4 mini PCs.

## Hardware

| Node   | IP          | Role                            | Hardware                  |
|--------|-------------|----------------------------------|---------------------------|
| node1  | 10.0.20.11  | K3s cluster-init (etcd leader)  | HP EliteDesk 800 G4 Mini  |
| node2  | 10.0.20.12  | K3s server join                 | HP EliteDesk 800 G4 Mini  |
| node3  | 10.0.20.13  | K3s server join                 | HP EliteDesk 800 G4 Mini  |
| nas    | 10.0.20.14  | TrueNAS SCALE (NFS storage)     | HP EliteDesk 800 G4 Mini  |

## Stack

| Layer       | Technology                            | Version    |
|-------------|----------------------------------------|------------|
| OS          | NixOS                                  | 25.05      |
| Cluster     | K3s (embedded etcd, HA)               | nixos-25.05 |
| GitOps      | ArgoCD                                 | v3 (7.8.0) |
| Ingress     | Traefik                                | v3 (33.2.1)|
| LoadBalancer| MetalLB                                | v0.15.3    |
| Storage     | Longhorn + TrueNAS NFS                 | 1.11       |
| Secrets     | sops-nix + age                         | —          |
| TLS         | cert-manager (DNS-01 via Cloudflare)   | v1.20      |
| Monitoring  | kube-prometheus-stack                  | 70.4.2     |

## Apps

Vaultwarden · Ghost · Silverbullet · Shelf · RoMM · Pelican · Actual Budget · Jellyfin · Jellyseerr · Homepage

## Deployment status

**Phase: Pre-deployment** — repo fully configured, hardware pending.

See [Node Provisioning](docs/node-provisioning.md) for the automated deployment guide.

## Documentation

- [Deployment Guide](docs/deployment-guide.md)
- [Node Provisioning](docs/node-provisioning.md)
- [Staging to Production TLS](docs/staging-to-prod.md)
- [Cert Manager TLS](docs/cert-manager-tls.md)
- [Gotchas](docs/gotchas.md)
- [Recovery](docs/recovery.md)

## Quick start

```bash
# Provision first node (run from workstation after booting node from Ventoy USB)
nix develop
bash scripts/smart-deploy.sh <temp-ip> node1 server-init

# Health check
bash scripts/health-check.sh --full
```
