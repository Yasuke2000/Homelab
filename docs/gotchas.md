# Gotchas & Hard-Won Lessons

Lessons learned the hard way. Read before touching anything.

---

## #1 Longhorn + NixOS PATH incompatibility

**Symptom:** Longhorn engine/replica pods crash with errors like:
```
exec: "mount": executable file not found in $PATH
exec: "blkid": executable file not found in $PATH
```

**Root cause:** Longhorn's engine image expects POSIX paths (`/bin`, `/usr/bin`).
NixOS puts binaries in `/run/current-system/sw/bin` and `/nix/store/...`.

**Fix:** Apply the Kyverno mutation policy in `infrastructure/kyverno-longhorn-fix.yaml`.
It mutates Longhorn DaemonSet pods to add a NixOS-compatible PATH via an init container
that bind-mounts the host's `/run/current-system/sw/bin` into the pod.

**Reference:** https://github.com/longhorn/longhorn/issues/2166

---

## #2 K3s token must use tokenFile, never inline

**Symptom:** Token ends up in `/nix/store/` which is world-readable (mode 444).
Any local user can read the cluster join token.

**Wrong:**
```nix
services.k3s.token = "mysecrettoken";  # ← lands in /nix/store/
```

**Correct:**
```nix
services.k3s.tokenFile = config.sops.secrets."k3s/token".path;
sops.secrets."k3s/token" = { mode = "0400"; };
```

---

## #3 UDP 8472 must be open — DNS breaks without it

**Symptom:** Pods can't resolve `*.cluster.local`, `*.svc.cluster.local`, or
external DNS. `kubectl exec -it pod -- nslookup kubernetes` returns NXDOMAIN.

**Root cause:** Flannel uses VXLAN encapsulation on UDP port 8472 for pod-to-pod
traffic. NixOS firewall drops it by default. CoreDNS queries never reach their target.

**Fix:** Already in `common/default.nix`:
```nix
networking.firewall.allowedUDPPorts = [ 8472 ];
```

**If you ever move to Cilium or Calico:** the port changes. Check the CNI docs.

---

## #4 ArgoCD v3 requires --server-side apply

**Symptom:** `kubectl apply` fails with:
```
Apply failed with 1 conflict: conflict with "helm" using apps/v1
```

**Fix:**
```bash
kubectl apply --server-side --force-conflicts -f manifest.yaml
```

Also set in ArgoCD Application manifests:
```yaml
syncOptions:
  - ServerSideApply=true
```

---

## #5 Never use the K3s bash install script on NixOS

**Symptom:** K3s installs but breaks after `nixos-rebuild switch`. The systemd
unit disappears or the binary path changes.

**Root cause:** The bash installer puts files in `/usr/local/bin/` which doesn't
exist after a NixOS rebuild. NixOS's K3s module manages everything declaratively.

**Fix:** Only ever use `services.k3s.*` NixOS options. Never run:
```bash
curl -sfL https://get.k3s.io | sh -   # ← NEVER on NixOS
```

---

## #6 LF line endings — CRLF breaks nix eval

**Symptom:** `nix flake check` fails with cryptic parse errors like:
```
error: syntax error, unexpected $end, expecting ';'
```
even though the file looks correct in your editor.

**Root cause:** Windows CRLF line endings (`\r\n`) inside `.nix` files confuse
the Nix parser. The `\r` character is treated as part of identifiers.

**Fix:** `.gitattributes` enforces LF on commit. If you already have CRLF files:
```bash
git add --renormalize .
```

---

## #7 NixOS SSH option casing is case-sensitive

**Symptom:** Password authentication remains enabled despite setting it to false.

**Wrong (silently ignored):**
```nix
services.openssh.settings.passwordAuthentication = false;
```

**Correct:**
```nix
services.openssh.settings.PasswordAuthentication = false;
```

NixOS maps these directly to the `sshd_config` directive names which are
case-sensitive in some NixOS module versions.

---

## #8 etcd upgrade path before K3s v1.34+

**Context:** K3s bundles etcd. K3s versions using etcd < 3.5.26 have a known
data corruption bug when upgrading directly to etcd 3.6.x (bundled in K3s v1.34+).

**Safe upgrade path:**
1. Upgrade K3s to the last release that bundles etcd 3.5.26
2. Verify etcd is healthy: `k3s etcd-snapshot ls`
3. Then upgrade to K3s v1.34+

**Check current etcd version:**
```bash
k3s etcd-snapshot ls
# or
crictl exec $(crictl ps | grep etcd | awk '{print $1}') etcd --version
```

---

## MetalLB — CRDs only, never ConfigMap mode

MetalLB v0.15+ removed ConfigMap support. Always use CRD-based config:

```yaml
# CORRECT — CRD based
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: homelab-pool
  namespace: metallb-system
spec:
  addresses:
    - 10.0.20.100-10.0.20.200
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: homelab-l2
  namespace: metallb-system
```

```yaml
# WRONG — ConfigMap mode (removed in v0.14+)
apiVersion: v1
kind: ConfigMap
metadata:
  name: config
  namespace: metallb-system
```

---

## Traefik v3 — v2 rule syntax is deprecated

**Symptom:** IngressRoute works but logs show deprecation warnings, or routing
fails silently after upgrading from Traefik v2.

**Wrong (v2 syntax):**
```yaml
rule: "Host:example.com"                    # old
rule: "PathPrefix:/api"                     # old
```

**Correct (v3 syntax):**
```yaml
rule: "Host(`example.com`)"                 # backticks required
rule: "PathPrefix(`/api`)"
rule: "Host(`example.com`) && PathPrefix(`/api`)"
```

---

## NFS mounts from TrueNAS — options matter

Recommended NFS mount options for K8s PVs on TrueNAS SCALE:
```
nfsvers=4.1,hard,intr,rsize=1048576,wsize=1048576,timeo=600
```

Avoid `soft` mounts — a soft NFS timeout causes silent data corruption.

---

## #9 openiscsi package name (no hyphen)

**Symptom:** `nix flake check` fails with `undefined variable 'open-iscsi'`.

**Fix:** The correct nixpkgs package name is `openiscsi` (no hyphen):

```nix
environment.systemPackages = with pkgs; [ openiscsi ];  # correct
# NOT: open-iscsi  ← undefined
```

---

## #10 .sops.yaml age recipient indentation

**Symptom:** yamllint fails with "wrong indentation: expected X but found Y"
on the age recipient lines.

**Fix:** Age recipients must be at exactly 10 spaces of indentation:
```yaml
creation_rules:
  - path_regex: secrets/.*\.yaml$
    key_groups:
      - age:
          - *workstation   # ← 10 spaces
```

---

## #11 Grafana admin password via existingSecret

**Symptom:** Grafana Helm chart with `adminPassword: "hardcoded"` in values.yaml
exposes the password in git history.

**Fix:** Use `existingSecret` with a sops-encrypted Kubernetes Secret:
```yaml
# In Helm values:
admin:
  existingSecret: grafana-admin-secret
  userKey: admin-user
  passwordKey: admin-password
```
The secret itself is in `apps/monitoring/manifests/secret.yaml` (sops-encrypted).

---

## #12 K3s token immutability after cluster bootstrap

**Symptom:** Changing `k3s/token` in secrets.yaml after cluster init causes nodes
to be unable to rejoin — the token is burned into etcd at `cluster-init`.

**Rule:** The K3s cluster token is **immutable** after `--cluster-init`. Never
rotate it while the cluster is running. If you must change it, full cluster
rebuild is required.

---

## #13 systemd-networkd conflicts with networking.interfaces

**Symptom:** Network comes up on wrong interface, or doesn't come up at all.
Boot logs show conflicting configuration.

**Root cause:** Mixing `networking.interfaces` with `networking.useNetworkd = true`
causes both networkd and scripted networking to fight over the interface.

**Fix:** With `networking.useNetworkd = true`, use only `systemd.network.networks`:

```nix
# CORRECT
networking.useNetworkd = true;
systemd.network.networks."10-lan" = { ... };

# WRONG — conflicts with networkd
networking.interfaces."eno1".ipv4.addresses = [ ... ];
```

---

## #14 nixos-facter is alpha software

nixos-facter auto-generates hardware configs from live hardware. Useful for
discovery, but its output format is unstable. Do not commit generated facter
configs as-is — review and hand-edit them first.
