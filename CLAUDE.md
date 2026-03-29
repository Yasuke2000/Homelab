# Homelab — Project Context

## Project summary
Sovereign bare-metal NixOS homelab. Three HP mini PCs (ProDesk 400 G7 SFF + 2x EliteDesk 800) running
K3s HA cluster (embedded etcd). Synology DS918+ NAS (NFS storage).
GitOps via ArgoCD v3. All secrets via sops-nix + age.

## Current deployment status (updated 2026-03-18)
**Phase: Pre-deployment — repo is fully configured, nodes not yet provisioned.**

| What | Status |
|------|--------|
| NixOS configs (node1/2/3) | Ready — NIC/disk names are templates, fill after hardware check |
| secrets/secrets.yaml | Encrypted with sops age |
| All app Kubernetes Secrets | Encrypted with sops age |
| .sops.yaml | Workstation key only — node keys added after first deploy |
| CI (yaml-lint, kubeconform, sops-check, line-endings) | Passing |
| CI (nix flake check) | Passing |
| GitHub issues | #14 Fase 2, #15 Fase 3, #16 Fase 4, #17 Fase 5, #18 Fase 6 |

**Next action: Issue #14 — boot nodes from NixOS ISO and run collect-hardware-info.sh**

## Age key location
- Private key: `C:\Users\DavidD\.config\sops\age\keys.txt` (Windows)
- Backup: private GitHub repo `Yasuke2000/homelab-secrets`
- Public key: `age1m483x92dqmkazqx8xu7xc8waw3uh23a890uv4tcj6d4xafg98alqq0vqeh`
- sops tools: `sops.exe` and `age.exe` at `C:\Users\DavidD\AppData\Local\Temp\` (re-download if needed)

## sops usage on Windows (no WSL2)
```powershell
# Decrypt/edit a secret
$env:SOPS_AGE_KEY_FILE="C:\Users\DavidD\.config\sops\age\keys.txt"
C:\Users\DavidD\AppData\Local\Temp\sops.exe secrets/secrets.yaml

# Encrypt a new file
$env:SOPS_AGE_KEY_FILE="C:\Users\DavidD\.config\sops\age\keys.txt"
C:\Users\DavidD\AppData\Local\Temp\sops.exe --encrypt --config /dev/null `
  --age age1m483x92dqmkazqx8xu7xc8waw3uh23a890uv4tcj6d4xafg98alqq0vqeh `
  --in-place path/to/secret.yaml
```

## Node IPs (VLAN 20 — 10.0.20.0/24)
| Node   | IP           | Role                          |
|--------|-------------|-------------------------------|
| node1  | 10.0.20.11  | K3s cluster-init (etcd leader)|
| node2  | 10.0.20.12  | K3s server join               |
| node3  | 10.0.20.13  | K3s server join               |
| nas    | 10.0.20.14  | Synology DS918+ (NFS)           |
| gw     | 10.0.20.1   | UniFi gateway                 |

## Software versions (pinned)
- NixOS: 25.05
- K3s: latest stable on nixos-25.05 channel
- ArgoCD: v3 (Helm chart 7.8.0) — MUST use `--server-side --force-conflicts`
- MetalLB: v0.15.3 — CRDs only, NEVER ConfigMap mode
- Traefik: v3 (Helm chart 33.2.1) — v2 rule syntax is DEPRECATED
- Longhorn: v1.11 (Helm chart 1.11.0) — requires Kyverno PATH workaround on NixOS
- cert-manager: v1.20 (Helm chart v1.20.0)
- Kyverno: 3.4.0
- kube-prometheus-stack: 70.4.2
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

### 9. NixOS package name: openiscsi (not open-iscsi)
In `environment.systemPackages`, use `openiscsi` (no hyphen).
`open-iscsi` is an undefined variable in nixpkgs and breaks `nix flake check`.

### 10. sops.yaml indentation — age recipients must be at 10 spaces
```yaml
creation_rules:
  - path_regex: ...
    key_groups:
      - age:
          - *workstation   # 10 spaces — NOT 8
```
8-space indentation causes yamllint errors in CI.

### 11. Grafana admin credentials via Kubernetes Secret
Grafana admin password is in `apps/monitoring/manifests/secret.yaml` (sops-encrypted).
Helm values reference it via `grafana.admin.existingSecret: grafana-admin-secret`.
Do NOT put the password inline in application.yaml.

## Repository structure
```
homelab/
├── .github/workflows/   GitHub Actions CI
├── hosts/               Per-node NixOS config (hostname, IP, disk)
├── common/              Shared NixOS config (all nodes)
├── modules/             Reusable NixOS modules (K3s, disko)
├── apps/                ArgoCD Application manifests + Helm values
│   ├── app-of-apps.yaml Root ArgoCD Application
│   └── */manifests/     Kubernetes manifests per app (secrets encrypted)
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
bash scripts/deploy-node.sh node1

# Join nodes after node1 is running
bash scripts/deploy-node.sh node2
bash scripts/deploy-node.sh node3
```

### Rebuild a running node
```bash
nixos-rebuild switch --flake .#node1 --target-host root@10.0.20.11
```

### Bootstrap ArgoCD (run once after K3s is up)
```bash
bash scripts/bootstrap-argocd.sh
kubectl apply -f apps/app-of-apps.yaml
```

### Edit secrets (Windows — no WSL2)
```bash
# In Git Bash:
SOPS_AGE_KEY_FILE="/c/Users/DavidD/.config/sops/age/keys.txt" \
  /c/Users/DavidD/AppData/Local/Temp/sops.exe secrets/secrets.yaml
```

### Add node age keys after deploy (Fase 4)
```bash
# Get key from each node:
ssh root@10.0.20.11 'nix-shell -p ssh-to-age --run "ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub"'
# Then add to .sops.yaml and run:
sops updatekeys secrets/secrets.yaml
```

### Check flake
```bash
nix flake check --no-build
```

## Installed GitHub integrations
- **Renovate** — automatic dependency PRs for Helm chart versions, Nix inputs (GitHub App, no PAT needed)
- **CodeRabbit** — AI code review on PRs
- **Codacy** — static analysis
- **Netlify** — preview deploys (if docs site is added)
