# David's Homelab

A production-grade bare-metal infrastructure project built for learning, self-hosting,
and demonstrating real-world engineering skills. Every node, every certificate, every
secret, and every deployment is managed entirely through code.

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
                More["+ 8 more apps"]
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
| Vaultwarden | vault.daviddelporte.com | Password manager (Bitwarden-compatible) |
| Ghost | daviddelporte.com | Personal blog |
| Jellyfin | jellyfin.daviddelporte.com | Media server |
| Jellyseerr | requests.daviddelporte.com | Media request management |
| RoMM | romm.daviddelporte.com | ROM / game library manager |
| Pelican | games.daviddelporte.com | Game server management |
| Actual Budget | budget.daviddelporte.com | Personal finance |
| Silverbullet | notes.daviddelporte.com | Personal knowledge base |
| Shelf | shelf.daviddelporte.com | Book tracking |
| Homepage | home.daviddelporte.com | Self-hosted dashboard |
| Uptime Kuma | status.daviddelporte.com | Uptime monitoring and status page |
| Grafana | grafana.daviddelporte.com | Metrics and alerting |

---

## Engineering highlights

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

## Why bare-metal over cloud?

| | Bare-metal homelab | Equivalent cloud |
|---|---|---|
| **Monthly cost** | ~€5 (electricity) | ~€80–150 |
| **Data sovereignty** | Full — nothing leaves home | Vendor-controlled |
| **Learning depth** | Hardware, OS, networking, K8s | Managed services only |
| **Vendor lock-in** | None | High |

The goal was to build something that mirrors production infrastructure — with
real failure modes, real networking constraints, and real operational runbooks —
not a managed service that abstracts all the interesting problems away.

---

## CI / CD pipeline

Every push to `master` runs 5 automated checks:

| Check | What it validates |
|---|---|
| `nix flake check` | All NixOS configurations build without errors |
| `yamllint` | All YAML manifests pass linting |
| `kubeconform` | All Kubernetes manifests validate against API schemas |
| `sops-check + trufflehog` | No plaintext secrets committed |
| `line-endings` | LF only (CRLF breaks the Nix parser) |
