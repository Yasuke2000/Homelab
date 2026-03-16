# Homelab — Project Context

## Project summary
Sovereign bare-metal NixOS homelab. Three HP EliteDesk 800 G4 mini PCs running
K3s HA cluster (embedded etcd). One HP EliteDesk running TrueNAS SCALE (NFS storage).
GitOps via ArgoCD v3. All secrets via sops-nix + age.

## Node IPs (VLAN 20 — 10.0.20.0/24)
| Node   | IP           | Role                          |
|--------|-------------|-------------------------------|
| node1  | 10.0.20.11  | K3s cluster-init (etcd leader)|
| node2  | 10.0.20.12  | K3s server join               |
| node3  | 10.0.20.13  | K3s server join               |
| nas    | 10.0.20.14  | TrueNAS SCALE (NFS)           |
| gw     | 10.0.20.1   | UniFi gateway                 |

## Software versions (pinned)
- NixOS: 25.05
- K3s: latest stable on nixos-25.05 channel
- ArgoCD: v3 (Helm chart ~7.x) — MUST use `--server-side --force-conflicts`
- MetalLB: v0.15.3 — CRDs only, NEVER ConfigMap mode
- Traefik: v3 (Helm chart ~33.x) — v2 rule syntax is DEPRECATED
- Longhorn: v1.11 — requires Kyverno PATH workaround on NixOS
- cert-manager: v1.20
- sops-nix: follows nixpkgs

## Critical gotchas — READ BEFORE EDITING

### 1. Longhorn + NixOS PATH bug
Longhorn's engine image expects system binaries (mount, blkid, etc.) in `/usr/bin`
and `/bin`. NixOS puts them in `/run/current-system/sw/bin`. Without the Kyverno
mutation policy in `infrastructure/kyverno-longhorn-fix.yaml`, Longhorn pods crash.

### 2. K3s token — NEVER inline
Always use `services.k3s.tokenFile` pointing to a sops-managed secret.
Inline tokens end up in the Nix store (world-readable). See `modules/k3s-server-init.nix`.

### 3. UDP 8472 (Flannel VXLAN) must be open
Without `allowedUDPPorts = [ 8472 ]` in the NixOS firewall, pod-to-pod DNS
completely breaks. This causes mysterious `NXDOMAIN` errors inside pods.
Already set in `common/default.nix`.

### 4. ArgoCD v3 apply command
```bash
kubectl apply --server-side --force-conflicts -f argocd-install.yaml
```
Regular `kubectl apply` fails with field manager conflicts on ArgoCD v3 CRDs.

### 5. K3s NixOS module — no bash install script
Use `services.k3s.*` NixOS options exclusively. The upstream bash installer
(`curl | bash`) bypasses NixOS's declarative management and breaks on rebuilds.

### 6. Line endings — LF only
All `.nix`, `.yaml`, `.sh` files must use LF (Unix) line endings.
CRLF causes `nix eval` to fail with cryptic parse errors.
`.gitattributes` enforces this at git level.

### 7. NixOS SSH option casing
```nix
# CORRECT
services.openssh.settings.PasswordAuthentication = false;
# WRONG — silently ignored
services.openssh.settings.passwordAuthentication = false;
```

### 8. etcd upgrade path
Before upgrading to K3s v1.34+, ensure etcd is at 3.5.26.
K3s bundles etcd — upgrading K3s also upgrades etcd. Check K3s release notes.

## Repository structure
```
homelab/
├── .github/workflows/   GitHub Actions CI
├── hosts/               Per-node NixOS config (hostname, IP, disk)
├── common/              Shared NixOS config (all nodes)
├── modules/             Reusable NixOS modules (K3s, disko)
├── apps/                ArgoCD Application manifests + Helm values
│   └── app-of-apps.yaml Root ArgoCD Application
├── infrastructure/      Cluster-level K8s manifests (namespaces, Kyverno)
├── secrets/             sops-encrypted secrets (NEVER commit plaintext)
├── docs/                Runbooks and gotchas
├── flake.nix            Nix flake entrypoint
└── .sops.yaml           sops age key configuration
```

## Common commands

### Deploy a node (first time)
```bash
# From your workstation (nix develop to get tools)
nix develop

# Deploy node1 (wipes disk and installs NixOS)
nixos-anywhere --flake .#node1 root@10.0.20.11

# Join nodes after node1 is running
nixos-anywhere --flake .#node2 root@10.0.20.12
nixos-anywhere --flake .#node3 root@10.0.20.13
```

### Rebuild a running node
```bash
nixos-rebuild switch --flake .#node1 --target-host root@10.0.20.11
```

### Bootstrap ArgoCD (run once after K3s is up)
```bash
kubectl create namespace argocd
kubectl apply --server-side --force-conflicts \
  -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Then apply the app-of-apps
kubectl apply -f apps/app-of-apps.yaml
```

### Edit secrets
```bash
sops secrets/secrets.yaml
```

### Check flake
```bash
nix flake check
```

## Installed GitHub integrations
- **Renovate** — automatic dependency PRs for Helm chart versions, Nix inputs
- **CodeRabbit** — AI code review on PRs
- **Codacy** — static analysis
- **Netlify** — preview deploys (if docs site is added)
