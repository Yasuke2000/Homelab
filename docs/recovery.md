# Recovery Guide

What to do when things go wrong.

## Age private key location

| Location | Path |
|----------|------|
| Windows workstation | `C:\Users\DavidD\.config\sops\age\keys.txt` |
| Private backup repo | `github.com/Yasuke2000/homelab-secrets` (private) |

**Public key:** `age1m483x92dqmkazqx8xu7xc8waw3uh23a890uv4tcj6d4xafg98alqq0vqeh`

## If the workstation age key is lost

All secrets are encrypted to this key. Without it you cannot decrypt `secrets/secrets.yaml`
or any `apps/*/manifests/secret.yaml`.

### Recovery steps

1. Retrieve the private key from `github.com/Yasuke2000/homelab-secrets`
2. Place it at `C:\Users\DavidD\.config\sops\age\keys.txt`
3. Verify: `sops.exe --decrypt secrets/secrets.yaml`

### If the backup is also lost (worst case)

You must re-create all secrets from scratch:

```bash
# 1. Generate a new age key
age-keygen -o keys.txt

# 2. Update .sops.yaml with the new public key
# Replace the &workstation line with the new public key

# 3. Re-encrypt secrets.yaml with known plaintext values
# Edit secrets/secrets.yaml with sops (it will encrypt on save)
$env:SOPS_AGE_KEY_FILE="C:\Users\DavidD\.config\sops\age\keys.txt"
sops.exe secrets/secrets.yaml

# 4. Re-encrypt all app secrets the same way
# For each apps/*/manifests/secret.yaml

# 5. Update the backup repo with the new key
```

Secret values to re-enter (retrieve from running cluster if still up):
- `k3s.token` — `kubectl -n kube-system get secret k3s-serving -o jsonpath='{.data.token}' | base64 -d`
- Vaultwarden admin token — visible in Vaultwarden admin panel
- Ghost DB password — `kubectl get secret ghost-db-secret -n ghost -o jsonpath='{.data.password}' | base64 -d`
- All other passwords — retrieve from running pods or reset via app admin UI

## If a node's SSH host key is lost

The node age key is derived from its SSH host key. If a node needs to be
re-deployed (disk wipe), smart-deploy.sh generates a new SSH host key
automatically. This also means a new age key — you must update `.sops.yaml`
and re-encrypt secrets.

```bash
# Re-deploy the node (generates new SSH host key + age key automatically)
bash scripts/smart-deploy.sh <new-ip> nodeX <role>
```

## If etcd is corrupted

K3s automatically snapshots etcd. Snapshots are stored at
`/var/lib/rancher/k3s/server/db/snapshots/` on each control-plane node.

```bash
# List snapshots
ssh root@10.0.20.11 k3s etcd-snapshot ls

# Restore from a snapshot (stops cluster, restores, restarts)
ssh root@10.0.20.11 k3s etcd-snapshot restore <snapshot-name>
```

## If a node won't boot after nixos-rebuild

Roll back via the bootloader (systemd-boot):

1. Reboot the node
2. At the systemd-boot menu, select a previous NixOS generation
3. SSH in and run `nixos-rebuild switch --rollback`

Or from your workstation:
```bash
ssh root@10.0.20.1X "nixos-rebuild switch --rollback"
```

## Cluster nuclear option (full rebuild)

If the cluster is unrecoverable:

```bash
# 1. Back up persistent data from Longhorn volumes (if accessible)
# 2. Wipe and re-deploy node1
bash scripts/smart-deploy.sh <temp-ip> node1 server-init

# 3. Re-deploy node2 and node3
bash scripts/smart-deploy.sh <temp-ip> node2 server-join
bash scripts/smart-deploy.sh <temp-ip> node3 server-join

# 4. Re-bootstrap ArgoCD
bash scripts/bootstrap-argocd.sh

# 5. ArgoCD will re-sync all apps from git
kubectl apply -f apps/app-of-apps.yaml
```

All application configuration is in git. The only data that may be lost
is Longhorn volume data (databases, uploaded files). Back up databases
regularly via the apps' own backup mechanisms.
