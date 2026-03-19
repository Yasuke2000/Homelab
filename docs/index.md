# David's Homelab

A production-grade bare-metal infrastructure project — fully declarative, GitOps-driven,
and secured by design. Every node, every certificate, every secret, and every deployment
is managed entirely through code.

**Cluster**: 3-node K3s HA (embedded etcd) + TrueNAS NAS
**Running cost**: ~€17/month (electricity + domain)

---

## Architecture

```mermaid
graph TB
    subgraph Internet["Internet"]
        User((User)) -->|HTTPS| CF["Cloudflare\nDNS + Proxy"]
    end

    subgraph Home["Home Network — VLAN 20  ·  10.0.20.0/24"]
        CF -->|443| Traefik["Traefik v3\nIngress Controller\n10.0.20.100"]

        subgraph Cluster["K3s HA Cluster — embedded etcd"]
            Traefik --> Apps

            subgraph CP["Control Plane  ×3"]
                N1["node1  ·  10.0.20.11\netcd leader"]
                N2["node2  ·  10.0.20.12"]
                N3["node3  ·  10.0.20.13"]
                N1 --- N2
                N2 --- N3
            end

            subgraph Apps["Self-hosted Applications"]
                direction LR
                Vault["Vaultwarden"]
                Ghost["Ghost"]
                Jelly["Jellyfin"]
                More["+ 9 more apps"]
            end

            ArgoCD["ArgoCD v3\nGitOps Controller"] -.->|"git push → sync"| Apps
            Longhorn["Longhorn\nDistributed Storage"] --> Apps
        end

        NAS["TrueNAS SCALE\n10.0.20.14\nNFS storage"]
        NAS --> Longhorn
    end

    subgraph Git["Source of Truth"]
        Repo[("GitHub\nNixOS configs\nK8s manifests\nEncrypted secrets")]
    end

    Repo -->|reconcile| ArgoCD
```

---

## Tech Stack

| Layer | Technology | Version | Purpose |
|---|---|---|---|
| **OS** | NixOS | 25.05 | Declarative, reproducible — entire OS in code |
| **Cluster** | K3s (embedded etcd) | nixos-25.05 | Lightweight HA Kubernetes, no external etcd |
| **GitOps** | ArgoCD | v3 (chart 7.8.0) | Self-healing — cluster always matches git |
| **Secrets** | sops-nix + age | follows nixpkgs | Secrets encrypted in git, zero secret server |
| **Ingress** | Traefik | v3 (chart 33.2.1) | Dynamic routing via Kubernetes CRDs |
| **Load balancer** | MetalLB | v0.15.3 | Bare-metal LoadBalancer IPs via L2 |
| **Storage** | Longhorn + TrueNAS NFS | 1.11.0 | Replicated block storage + NAS for media |
| **TLS** | cert-manager + Cloudflare | v1.20.0 | Automatic wildcard certs via DNS-01 |
| **Policy** | Kyverno | 3.4.0 | Mutation policies (NixOS PATH fix for Longhorn) |
| **Monitoring** | kube-prometheus-stack | 70.4.2 | Prometheus + Grafana + Alertmanager |

---

## Self-hosted Applications

| App | Subdomain | Purpose |
|---|---|---|
| Ghost | daviddelporte.com | Personal blog / website |
| Vaultwarden | vault.daviddelporte.com | Password manager (Bitwarden-compatible) |
| Jellyfin | jellyfin.daviddelporte.com | Media server |
| Jellyseerr | requests.daviddelporte.com | Media request management |
| RoMM | romm.daviddelporte.com | ROM / game library manager |
| Pelican | games.daviddelporte.com | Game server management |
| Actual Budget | budget.daviddelporte.com | Personal finance |
| SilverBullet | notes.daviddelporte.com | Personal knowledge base |
| Shelf | shelf.daviddelporte.com | Book tracking |
| Homepage | home.daviddelporte.com | Self-hosted dashboard (all apps in one place) |
| Uptime Kuma | status.daviddelporte.com | Uptime monitoring and public status page |
| Grafana | grafana.daviddelporte.com | Metrics, dashboards, and alerting |
| Longhorn UI | longhorn.daviddelporte.com | Storage management |
| ArgoCD | argocd.daviddelporte.com | GitOps deployment management |

---

## Engineering Highlights

### Fully declarative infrastructure

Every node is defined in a NixOS flake. Provisioning a new bare-metal machine
is a single command — the script discovers hardware, generates cryptographic keys,
encrypts secrets for that specific node, installs NixOS, and verifies cluster
membership, all without touching the machine manually.

```bash
bash scripts/smart-deploy.sh 192.168.1.50 node1 server-init
```

### Secrets encrypted in git

All secrets (database passwords, API tokens, TLS credentials) are encrypted with
[age](https://age-encryption.org/) using sops. They live in the public repo as
encrypted blobs — readable only by machines whose keys are in `.sops.yaml`.
No secret server, no environment variables in CI, no risk of accidental exposure.

### Self-healing GitOps

ArgoCD monitors the git repo and continuously reconciles the cluster to match it.
If someone manually edits a resource, ArgoCD reverts it within minutes.
New apps are added by committing a Helm `Application` manifest — no `kubectl apply`
needed.

### Automatic rolling upgrades

```bash
bash scripts/upgrade-cluster.sh
```

Upgrades nodes one at a time (workers first, etcd leader last), verifies each
node is `Ready` before continuing, and rolls back automatically on failure.

---

## Skills Demonstrated

| Area | What this project covers |
| ---- | ------------------------ |
| **Linux / NixOS** | Declarative OS config, flakes, custom modules, systemd-networkd |
| **Kubernetes** | K3s HA cluster, RBAC, CRDs, resource management, rolling upgrades |
| **GitOps** | ArgoCD sync-waves, app-of-apps pattern, self-healing reconciliation |
| **Networking** | VLAN segmentation, DNS (Cloudflare), reverse proxy (Traefik), MetalLB L2 |
| **Security** | sops + age encryption, zero-trust secrets, automated secret rotation per node |
| **TLS / PKI** | cert-manager DNS-01 challenge, wildcard certificates, staging-to-prod promotion |
| **Storage** | Longhorn distributed block storage, NFS integration, automated snapshots + backups |
| **Monitoring** | Prometheus + Grafana + Alertmanager, custom alert routing |
| **CI/CD** | GitHub Actions (5 checks), yamllint, kubeconform, secret scanning, line-ending enforcement |
| **IaC** | Nix flakes, disko (declarative disk partitioning), nixos-anywhere remote deployment |
| **Automation** | Bash provisioning scripts, hardware auto-discovery, zero-touch node onboarding |

---

## Cost Efficiency

| Metric | Value |
| ------ | ----- |
| **Monthly running cost** | ~€17 (electricity + domain) |
| **Software licensing** | €0 — 100% open source |
| **Cloud equivalent** | €80–200/month for the same workload |
| **Break-even vs cloud** | 6–12 months |

See [Hardware & Cost](hardware.md) for the full breakdown.

---

## Why bare-metal?

This project mirrors production infrastructure with real failure modes, real
networking constraints, and real operational runbooks — not a managed service
that abstracts the interesting problems away.

| Metric | Bare-metal | Cloud equivalent |
| ------ | ---------- | ---------------- |
| **Monthly cost** | ~€17 | €80–200 |
| **Data sovereignty** | Full — nothing leaves the network | Vendor-controlled |
| **Learning depth** | Hardware, OS, networking, K8s | Managed services only |
| **Vendor lock-in** | None | High |

---

## Documentation

| Guide | What it covers |
|---|---|
| [Deployment Guide](deployment-guide.md) | Boot to fully running cluster — step by step |
| [Node Provisioning](node-provisioning.md) | How smart-deploy.sh works, Ventoy USB setup |
| [Hardware & Cost](hardware.md) | Full bill of materials, running costs, sourcing guide |
| [Cert Manager TLS](cert-manager-tls.md) | DNS-01 setup, staging vs production, troubleshooting |
| [Alerting](alerting.md) | Alertmanager Discord webhook setup |
| [Gotchas](gotchas.md) | 14 hard-won lessons from building this |
| [Recovery](recovery.md) | Lost age key, corrupted etcd, full cluster rebuild |
| [Staging to Production](staging-to-prod.md) | TLS certificate promotion checklist |
| [Next Steps](next-steps.md) | Concrete deployment checklist with copy-paste commands |

---

## CI / CD Pipeline

Every push to `master` runs 5 automated checks:

| Check | What it validates |
|---|---|
| `nix flake check` | All NixOS configurations build without errors |
| `yamllint` | All YAML manifests pass linting |
| `kubeconform` | All Kubernetes manifests validate against API schemas |
| `sops-check + trufflehog` | No plaintext secrets committed |
| `line-endings` | LF only (CRLF breaks the Nix parser) |
