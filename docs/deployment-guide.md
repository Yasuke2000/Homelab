# Deployment Guide — Stap voor stap

## Overzicht: wat is manueel vs automatisch?

```
JIJ doet:                          AUTOMATISCH:
─────────────────────────────────  ──────────────────────────────────────
1. Script runnen op elke node  →   Hardware info verzameld
2. Waarden invullen in repo    →   -
3. setup-age-keys.sh runnen    →   Age key gegenereerd
4. sops secrets invullen       →   Secrets versleuteld
5. deploy-node.sh runnen       →   NixOS geïnstalleerd + geconfigureerd
6. bootstrap-argocd.sh runnen  →   ArgoCD geïnstalleerd
                               →   App of Apps gesyncet
                               →   Kyverno, MetalLB, Traefik... allemaal
                               →   Vaultwarden, Jellyfin, Ghost... allemaal
```

---

## FASE 0 — Voorbereiding (eenmalig, op je Windows pc)

### 0.1 Repo naar GitHub pushen
```bash
# In de homelab map:
git add .
git commit -m "feat: initial homelab baseline"
git push origin main
```

### 0.2 Vul je GitHub repo URL in
Vervang `Yasuke2000` in dit bestand:
- `apps/app-of-apps.yaml`
- Alle `apps/*/application.yaml` bestanden

---

## FASE 1 — Hardware info verzamelen (op ELKE node)

**Wat je nodig hebt:** een USB stick met de NixOS minimal ISO

**Download:** https://nixos.org/download → "Minimal ISO image" (x86_64)

### 1.1 Boot elke HP EliteDesk van de USB

### 1.2 Zorg dat je SSH hebt naar de node
```bash
# Op de node (via toetsenbord):
# NixOS live ISO heeft standaard geen root password → stel het in:
passwd root
# Of voeg je SSH key toe:
mkdir -p ~/.ssh && echo "ssh-ed25519 AAAA..." >> ~/.ssh/authorized_keys
```

### 1.3 Run het hardware-info script VAN JE PC naar de node
```bash
# Op je Windows pc (in WSL of Git Bash):
ssh root@10.0.20.11 'bash -s' < scripts/collect-hardware-info.sh node1
ssh root@10.0.20.12 'bash -s' < scripts/collect-hardware-info.sh node2
ssh root@10.0.20.13 'bash -s' < scripts/collect-hardware-info.sh node3
```

### 1.4 Wat je uit de output haalt
Het script toont zoiets als:
```
━━━ SUMMARY
  ┌─ hosts/nodeX/default.nix
  │  networking.interfaces."eno1" = { ... };   ← kopieer "eno1"
  └──────────────────────────────────────────

  ┌─ modules/disk-config.nix
  │  device = "/dev/nvme0n1";                  ← kopieer "nvme0n1"
  └──────────────────────────────────────────
```

### 1.5 Vul die waarden in het repo

**`modules/disk-config.nix`** — verander lijn 32:
```nix
device = "/dev/nvme0n1";   # ← jouw disk naam
```

**`hosts/node1/default.nix`** — verander lijn 14:
```nix
networking.interfaces."eno1" = {   # ← jouw NIC naam
```
Doe dit ook voor `hosts/node2` en `hosts/node3` (met het juiste IP per node).

---

## FASE 2 — Secrets instellen (op je pc, eenmalig)

### 2.1 Open de devshell (geeft je alle tools)
```bash
nix develop
# Je hebt nu: kubectl, helm, sops, age, nixos-anywhere, k9s
```

### 2.2 Genereer je age encryptie key
```bash
bash scripts/setup-age-keys.sh
```
Output:
```
✓ Generated new key at ~/.config/sops/age/keys.txt
✓ Pubkey: age1abc123...   ← kopieer dit
```

### 2.3 Zet de pubkey in `.sops.yaml`
Open `.sops.yaml` en vervang:
```yaml
- age1XXXXXXX...  # workstation
```
door je echte pubkey:
```yaml
- age1abc123...   # workstation
```
> De node-pubkeys (node1, node2, node3) vul je IN NA de eerste deploy (zie Fase 4).
> Voorlopig kan je die regels uitcommentariëren.

### 2.4 Versleutel de secrets
```bash
sops secrets/secrets.yaml
```
Dit opent je editor. Vul in:
```yaml
k3s:
    token: plak-hier-een-sterk-random-wachtwoord   # openssl rand -hex 32

vaultwarden:
    adminToken: plak-hier-een-token

# ... etc
```
Sla op en sluit → sops versleutelt automatisch.

### 2.5 Genereer flake.lock
```bash
nix flake update
```

### 2.6 Commit alles
```bash
git add flake.lock secrets/secrets.yaml .sops.yaml
git add hosts/ modules/
git commit -m "feat: add hardware config and encrypted secrets"
git push
```

---

## FASE 3 — NixOS deployen (nixos-anywhere)

nixos-anywhere verbindt via SSH met de node, wist de disk, en installeert NixOS volledig automatisch. Jij hoeft niets meer te doen op de node zelf.

### Altijd in volgorde: eerst node1, dan 2, dan 3!

```bash
# Node 1 — start het etcd cluster
bash scripts/deploy-node.sh node1
```

Output eindigt met:
```
✓ nixos-anywhere deploy complete for node1
```
De node herstart automatisch met NixOS.

**Wacht ~60 seconden**, verifieer dan:
```bash
ssh root@10.0.20.11 'systemctl status k3s'
# moet tonen: Active: active (running)
```

```bash
# Node 2 — joint het cluster
bash scripts/deploy-node.sh node2

# Node 3 — joint het cluster
bash scripts/deploy-node.sh node3
```

Verifieer dat alle 3 nodes in het cluster zitten:
```bash
ssh root@10.0.20.11 'k3s kubectl get nodes'
# Moet tonen:
# NAME             STATUS   ROLES                       AGE
# homelab-node1    Ready    control-plane,etcd,master   5m
# homelab-node2    Ready    control-plane,etcd,master   2m
# homelab-node3    Ready    control-plane,etcd,master   1m
```

---

## FASE 4 — Node age keys toevoegen aan sops (na deploy)

Nu de nodes draaien, hebben ze SSH host keys. Die zetten we om naar age keys zodat de nodes hun eigen secrets kunnen decrypteren.

```bash
# Haal age pubkey van elke node op
ssh root@10.0.20.11 'nix-shell -p ssh-to-age --run "ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub"'
ssh root@10.0.20.12 'nix-shell -p ssh-to-age --run "ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub"'
ssh root@10.0.20.13 'nix-shell -p ssh-to-age --run "ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub"'
```

Vul die 3 pubkeys in `.sops.yaml`:
```yaml
- age1node1xxx...   # node1
- age1node2yyy...   # node2
- age1node3zzz...   # node3
```

Herencrypteer de secrets met alle keys:
```bash
sops updatekeys secrets/secrets.yaml
```

Commit en push, dan rebuild de nodes:
```bash
git add .sops.yaml secrets/secrets.yaml
git commit -m "feat: add node age keys to sops"
git push

nixos-rebuild switch --flake .#node1 --target-host root@10.0.20.11
nixos-rebuild switch --flake .#node2 --target-host root@10.0.20.12
nixos-rebuild switch --flake .#node3 --target-host root@10.0.20.13
```

---

## FASE 5 — ArgoCD bootstrappen (eenmalig)

```bash
# Haal kubeconfig op van node1
scp root@10.0.20.11:/etc/rancher/k3s/k3s.yaml ./kubeconfig
# Pas het IP aan (k3s zet 127.0.0.1, wij willen het echte IP)
sed -i 's/127.0.0.1/10.0.20.11/' kubeconfig
export KUBECONFIG=$(pwd)/kubeconfig

# Bootstrap ArgoCD
bash scripts/bootstrap-argocd.sh
```

**Wat er daarna automatisch gebeurt** (ArgoCD sync-waves):
```
wave -5  →  Kyverno geïnstalleerd
wave -4  →  MetalLB geïnstalleerd + Kyverno Longhorn-fix geladen
wave -3  →  Traefik geïnstalleerd → krijgt IP 10.0.20.100 van MetalLB
wave -2  →  cert-manager geïnstalleerd
wave -1  →  Longhorn geïnstalleerd (werkt nu correct dankzij Kyverno fix)
wave  0  →  Alle apps: Vaultwarden, Jellyfin, Ghost, SilverBullet...
```

Volg de voortgang in de ArgoCD UI:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: https://localhost:8080
```

---

## FASE 6 — Domein + finale TODOs

Na fase 5 draaien alle apps maar zijn ze niet bereikbaar want de domeinen zijn nog `yourdomain.com`. Vertel me je domeinnaam en ik vervang alle TODOs in één keer.

**Andere finale TODOs:**
- TrueNAS NFS shares aanmaken (voor Jellyfin media, Longhorn backup, ROMs)
- Grafana admin wachtwoord instellen via sops
- Vaultwarden eerste gebruiker aanmaken

---

## Samenvatting: jij doet dit, de rest is automatisch

| Stap | Jij | Automatisch |
|------|-----|-------------|
| Hardware info | Script runnen op nodes | Info getoond |
| Waarden invullen | Disk naam, NIC naam in repo | — |
| Secrets | `sops secrets/secrets.yaml` openen en invullen | Versleuteld |
| NixOS deploy | `deploy-node.sh node1/2/3` | Disk wissen + NixOS installeren + K3s starten |
| K8s bootstrap | `bootstrap-argocd.sh` | Alle 13 apps deployen in volgorde |
| Domein invullen | Jouw domein doorgeven | Ik vervang alle TODOs |
