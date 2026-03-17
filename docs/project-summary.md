# Homelab Project Summary
> Gedetailleerde statusdocumentatie — voor gebruik door AI-assistenten en adviseurs
> Laatste update: 2026-03-18

---

## 1. Doel van het project

Sovereign bare-metal homelab op 4 HP EliteDesk 800 G4 mini-PC's:
- 3 nodes draaien een **K3s HA Kubernetes cluster** (embedded etcd, 3 control-plane nodes)
- 1 node draait **TrueNAS SCALE** als NAS/NFS storage server
- Alles wordt beheerd via **GitOps (ArgoCD v3)** — elke wijziging gaat via git push
- Secrets worden beheerd via **sops-nix + age** (nooit plaintext in git)
- Infrastructuur is volledig declaratief via **NixOS** (reproduceerbaar, geen config drift)

---

## 2. Hardware

| Node   | Hardware                    | IP           | Rol                              |
|--------|-----------------------------|--------------|----------------------------------|
| node1  | HP EliteDesk 800 G4 Mini    | 10.0.20.11   | K3s cluster-init (etcd leader)   |
| node2  | HP EliteDesk 800 G4 Mini    | 10.0.20.12   | K3s server join                  |
| node3  | HP EliteDesk 800 G4 Mini    | 10.0.20.13   | K3s server join                  |
| nas    | HP EliteDesk 800 G4 Mini    | 10.0.20.14   | TrueNAS SCALE (NFS storage)      |
| gw     | UniFi gateway               | 10.0.20.1    | Router/DNS voor VLAN 20          |

- **VLAN**: 10.0.20.0/24 (dedicated homelab VLAN)
- **MetalLB LoadBalancer IP range**: 10.0.20.100–10.0.20.200
- **Traefik LoadBalancer IP**: 10.0.20.100 (vaste toewijzing)

---

## 3. Software stack (pinned versies)

| Software        | Versie           | Helm chart               | Rol                               |
|-----------------|------------------|--------------------------|-----------------------------------|
| NixOS           | 25.05            | n/a                      | OS op alle 3 nodes                |
| K3s             | latest/25.05     | n/a                      | Kubernetes distributie            |
| ArgoCD          | v3 (chart 7.8.0) | argo/argo-cd             | GitOps controller                 |
| Kyverno         | 3.4.0            | kyverno/kyverno          | Policy engine                     |
| MetalLB         | 0.15.3           | metallb/metallb          | LoadBalancer IPs                  |
| Traefik         | v3 (chart 33.2.1)| traefik/traefik          | Ingress controller / reverse proxy|
| cert-manager    | v1.20.0          | jetstack/cert-manager    | TLS certificaten (Let's Encrypt)  |
| Longhorn        | 1.11.0           | longhorn/longhorn        | Distributed block storage (PVCs)  |
| sops-nix        | follows nixpkgs  | n/a                      | Secrets decryptie op NixOS boot   |

---

## 4. Domein & TLS

- **Domein**: `daviddelporte.com` (bij Cloudflare)
- **Email**: `admin@daviddelporte.com`
- **TLS methode**: DNS-01 via Cloudflare API (geen port forwarding nodig)
- **Certificaat type**: wildcard `*.daviddelporte.com` + `daviddelporte.com`
- **Huidige issuer in alle ingresses**: `letsencrypt-staging` (veilig voor eerste deploy)
- **Overstap naar prod**: pas NA verificatie dat staging certs aangemaakt worden

### Subdomains per service

| Service | Subdomain |
|---------|-----------|
| Ghost (website) | daviddelporte.com |
| ArgoCD | argocd.daviddelporte.com |
| Grafana | grafana.daviddelporte.com |
| Vaultwarden | vault.daviddelporte.com |
| Actual Budget | budget.daviddelporte.com |
| Homepage dashboard | home.daviddelporte.com |
| Jellyfin | jellyfin.daviddelporte.com |
| Jellyseerr | requests.daviddelporte.com |
| Pelican | games.daviddelporte.com |
| RomM | romm.daviddelporte.com |
| Shelf | shelf.daviddelporte.com |
| SilverBullet | notes.daviddelporte.com |
| Uptime Kuma | status.daviddelporte.com |
| Longhorn UI | longhorn.daviddelporte.com |
| Traefik dashboard | (uitgeschakeld) |

---

## 5. Repository structuur (GitHub: Yasuke2000/Homelab)

```
homelab/
├── .github/workflows/check.yml   CI pipeline (5 checks)
├── .sops.yaml                    sops age-key configuratie
├── .yamllint.yaml                yamllint regels
├── flake.nix                     Nix flake — NixOS configs voor alle nodes
├── common/default.nix            Gedeelde NixOS config (alle nodes)
├── modules/
│   ├── disk-config.nix           Disko disk layout (GPT + LVM)
│   ├── k3s-server-init.nix       K3s config voor node1 (clusterInit)
│   └── k3s-server-join.nix       K3s config voor node2 + node3
├── hosts/
│   ├── node1/default.nix         Hostname, IP, interface voor node1
│   ├── node2/default.nix         Hostname, IP, interface voor node2
│   └── node3/default.nix         Hostname, IP, interface voor node3
├── apps/                         ArgoCD Application manifests + Helm values
│   ├── app-of-apps.yaml          Root ArgoCD Application (deploy everything)
│   ├── argocd/                   ArgoCD zelf (self-managing)
│   ├── kyverno/                  Policy engine
│   ├── metallb/ + ip-pool.yaml   Load balancer
│   ├── traefik/                  Ingress controller
│   ├── cert-manager/
│   │   ├── application.yaml      Helm chart deployment
│   │   ├── cluster-issuer.yaml   DNS-01 via Cloudflare (staging + prod)
│   │   └── wildcard-certificate.yaml  *.daviddelporte.com wildcard cert
│   ├── longhorn/                 Storage
│   ├── monitoring/               Prometheus + Grafana + Alertmanager + Uptime Kuma + Alerting rules
│   ├── vaultwarden/              Bitwarden-compatibele password manager
│   ├── actual-budget/            Personal finance app
│   ├── ghost/                    Blog/website platform
│   ├── homepage/                 Dashboard / startpagina
│   ├── jellyfin/                 Media server
│   ├── jellyseerr/               Media request manager
│   ├── pelican/                  Game server management
│   ├── romm/                     ROM manager (retro games)
│   ├── shelf/                    Asset management
│   └── silverbullet/             Markdown wiki / second brain
├── infrastructure/
│   ├── namespaces.yaml           15 namespaces
│   └── kyverno-longhorn-fix.yaml Kritieke Kyverno policy voor Longhorn op NixOS
├── secrets/
│   └── secrets.yaml              TEMPLATE (nog niet encrypted, placeholders)
├── scripts/
│   ├── deploy-node.sh            Deploy 1 node via nixos-anywhere
│   ├── bootstrap-argocd.sh       ArgoCD bootstrap (eenmalig)
│   ├── setup-age-keys.sh         Age encryption keys genereren
│   ├── create-k8s-secrets.sh     K8s Secrets aanmaken vanuit sops (incl. Cloudflare token)
│   ├── collect-hardware-info.sh  Hardware info verzamelen van nodes
│   └── create-github-issues.sh   GitHub issues aanmaken
└── docs/
    ├── deployment-guide.md       Stap-voor-stap deployment guide
    ├── gotchas.md                8 kritieke valkuilen
    ├── cert-manager-tls.md       TLS setup documentatie
    ├── next-steps.md             Post-bootstrap checklist
    └── project-summary.md        Dit bestand
```

---

## 6. Alle applicaties — gedetailleerd overzicht

### 6.1 Infrastructuur (ArgoCD sync-waves, automatisch geordend)

| Wave | App | Chart versie | Namespace | Doel |
|------|-----|-------------|-----------|------|
| -10 | app-of-apps | n/a | argocd | Root: deployt alle andere apps |
| -5 | ArgoCD | 7.8.0 | argocd | GitOps controller, beheert zichzelf |
| -5 | Kyverno | 3.4.0 | kyverno | Policy engine + Longhorn NixOS fix |
| -4 | MetalLB | 0.15.3 | metallb-system | LoadBalancer IPs voor bare-metal |
| -3 | Traefik | 33.2.1 | traefik | Ingress + TLS-terminatie |
| -2 | cert-manager | v1.20.0 | cert-manager | Let's Encrypt TLS via Cloudflare DNS-01 |
| -1 | Longhorn | 1.11.0 | longhorn-system | Distributed block storage (PVCs) |

### 6.2 Monitoring stack

| App | Image/chart | Namespace | Ingress | Storage |
|-----|-------------|-----------|---------|---------|
| kube-prometheus-stack | chart 70.4.2 | monitoring | grafana.daviddelporte.com | Prometheus 20Gi, Grafana 5Gi, Alertmanager 2Gi |
| Uptime Kuma | louislam/uptime-kuma:1.23.15 | monitoring | status.daviddelporte.com | 1Gi Longhorn |
| Alerting rules | PrometheusRule CRD | monitoring | n/a | n/a |

Alerting rules dekken: node disk/memory/CPU, workloads (crash, OOM, replicas), etcd, Longhorn, cert-manager

### 6.3 Gebruikersapplicaties

| App | Image | Namespace | Ingress | Storage | Secrets |
|-----|-------|-----------|---------|---------|---------|
| Vaultwarden | vaultwarden/server:1.32.7 | vaultwarden | vault.daviddelporte.com | 5Gi | adminToken |
| Actual Budget | actualbudget/actual-server:25.1.0 | actual-budget | budget.daviddelporte.com | 2Gi | geen |
| Ghost | ghost:5.87.2-alpine | ghost | daviddelporte.com | 5Gi content + 5Gi MySQL | dbPassword |
| Homepage | ghcr.io/gethomepage/homepage:v0.9.10 | homepage | home.daviddelporte.com | ConfigMap | geen |
| Jellyfin | jellyfin/jellyfin:10.10.3 | media | jellyfin.daviddelporte.com | 10Gi config + NFS media | geen |
| Jellyseerr | fallenbagel/jellyseerr:2.5.2 | media | requests.daviddelporte.com | 1Gi | geen |
| Pelican Panel | ghcr.io/pelican-dev/panel:v1.0.5 | pelican | games.daviddelporte.com | 5Gi + 5Gi MySQL | dbPassword |
| RomM | rommapp/romm:3.7.3 | romm | romm.daviddelporte.com | 10Gi assets + 1Gi config + NFS ROMs + 5Gi MariaDB | dbPassword + secretKey |
| Shelf.nu | ghcr.io/shelf-nu/shelf.nu:2.6.3 | shelf | shelf.daviddelporte.com | 5Gi | sessionSecret |
| SilverBullet | ghcr.io/silverbulletmd/silverbullet:0.9.5 | silverbullet | notes.daviddelporte.com | 5Gi | password |

**NFS mounts** (vanuit TrueNAS SCALE op 10.0.20.14 — nog niet aangemaakt):
- `nfs://10.0.20.14:/mnt/datapool/media` → Jellyfin (read-only)
- `nfs://10.0.20.14:/mnt/datapool/roms` → RomM
- `nfs://10.0.20.14:/mnt/datapool/longhorn-backup` → Longhorn backups

---

## 7. Secrets beheer

### Hoe het werkt

1. **sops-nix** (NixOS niveau): decrypteert `secrets/secrets.yaml` op elke node bij boot → geeft K3s zijn token
2. **Kubernetes Secrets**: aangemaakt via `scripts/create-k8s-secrets.sh` (leest sops → maakt K8s Secrets)
3. **App deployments** refereren `secretKeyRef` naar de K8s Secrets — nooit plaintext

### Secrets overzicht

| Secret naam | Namespace | Sleutels | Genereren |
|-------------|-----------|----------|-----------|
| k3s token | sops-nix | token | `openssl rand -hex 32` |
| cloudflare-api-token | cert-manager | api-token | Cloudflare dashboard → API Tokens |
| vaultwarden-secrets | vaultwarden | adminToken | `openssl rand -base64 48` |
| ghost-secrets | ghost | dbPassword | `openssl rand -hex 16` |
| pelican-secrets | pelican | dbPassword | `openssl rand -hex 16` |
| romm-secrets | romm | dbPassword, secretKey | `openssl rand -hex 16/32` |
| shelf-secrets | shelf | sessionSecret | `openssl rand -base64 32` |
| silverbullet-secrets | silverbullet | password | `openssl rand -base64 32` |

### sops configuratie (.sops.yaml)

- **Encryptie methode**: age (asymmetrisch, geen GPG nodig)
- **Recipients**: workstation + node1 + node2 + node3 (allemaal nog placeholder — echte keys na deployment)
- **Regels**:
  - `secrets/*.yaml` → encrypted met alle 4 keys
  - `apps/*/manifests/secret.yaml` → encrypted met alle 4 keys

---

## 8. NixOS configuratie — kritieke details

### Disk layout (via disko)
```
/dev/sdX
├── EFI  512 MiB (vfat)
└── LVM Physical Volume (100% rest)
    └── homelab-vg
        ├── root  80 GiB ext4  →  /
        └── var   100% rest ext4 → /var
            ├── /var/lib/longhorn   (Longhorn replica storage)
            └── /var/lib/rancher    (containerd images)
```

### Firewall regels (common/default.nix)
| Protocol | Poort(en) | Doel |
|----------|-----------|------|
| TCP | 6443 | K3s API server |
| TCP | 2379-2380 | etcd peer/client |
| TCP | 10250 | Kubelet API |
| UDP | **8472** | **Flannel VXLAN** — KRITIEK voor pod DNS |

### K3s configuratie
- **node1**: `clusterInit: true`, advertiseAddress: 10.0.20.11, TLS SANs voor alle 3 nodes
- **node2/3**: server: `https://10.0.20.11:6443`
- **Uitgeschakeld**: traefik, servicelb, local-storage (wij beheren dit zelf)
- **Cgroup driver**: systemd
- **Flannel interface**: eno1 ← **TODO: verifiëren per node met collect-hardware-info.sh**

### Kyverno Longhorn fix (KRITIEK)
Longhorn verwacht binaries in `/usr/bin`, NixOS zet ze in `/run/current-system/sw/bin`.
Kyverno muteert alle Pods in `longhorn-system` met een init-container die symlinks aanmaakt.
**Zonder deze fix crashen alle Longhorn engine pods.**

---

## 9. CI/CD pipeline

Elke push/PR op master triggert 5 checks:

| Check | Tool | Wat het controleert |
|-------|------|---------------------|
| nix-flake-check | `nix flake check --no-build` | Nix evaluatie van alle node configs |
| yaml-lint | yamllint | YAML syntax en stijl (.yamllint.yaml) |
| kubeconform | kubeconform v1.33.0 | K8s manifest validatie (strict) |
| sops-check | grep + trufflehog | Secrets niet plaintext in git |
| line-endings | grep | LF-only in .nix/.yaml/.sh bestanden |

**Geïnstalleerde GitHub-apps:**
- **Renovate**: automatische PR's voor nieuwe Helm chart versies + Nix inputs
- **CodeRabbit**: AI code review op elke PR
- **Codacy**: statische analyse

---

## 10. Deployment volgorde (checklist)

### Fase 0 — Repository setup — KLAAR ✅
- [x] Repository aangemaakt op GitHub (Yasuke2000/Homelab)
- [x] Alle NixOS configs geschreven (flake, modules, hosts, common)
- [x] Alle Kubernetes manifests geschreven (18 apps, 15 namespaces)
- [x] Image versies gepind (geen :latest tags)
- [x] CI pipeline werkend (5 checks)
- [x] Scripts geschreven (deploy, bootstrap, secrets, hardware)
- [x] K8s Secret templates aangemaakt per app
- [x] Domein ingesteld: daviddelporte.com
- [x] cert-manager omgezet naar DNS-01 via Cloudflare
- [x] Wildcard cert geconfigureerd: *.daviddelporte.com
- [x] Alle ingresses op letsencrypt-staging (veilig voor eerste deploy)
- [x] Alerting rules aangemaakt (Prometheus)
- [x] Documentatie aangemaakt

### Fase 1 — Cloudflare API token — TODO (nu al doen)
- [ ] Cloudflare dashboard → My Profile → API Tokens → Create Token
  - Template: "Edit zone DNS"
  - Zone Resources: daviddelporte.com
- [ ] Token invullen in `secrets/secrets.yaml` onder `cloudflare.apiToken`

### Fase 2 — SSH key + Age keys — TODO (nu al doen, geen hardware nodig)
- [ ] SSH key genereren (als nog niet gedaan):
  `ssh-keygen -t ed25519 -C "homelab-admin"`
- [ ] SSH public key toevoegen aan `hosts/*/default.nix`
- [ ] Age key genereren: `bash scripts/setup-age-keys.sh`
- [ ] Workstation age pubkey invullen in `.sops.yaml`
- [ ] `secrets/secrets.yaml` invullen met alle waarden
- [ ] `sops secrets/secrets.yaml` → encrypten

### Fase 3 — Hardware inventaris — OPEN (wacht op nodes)
- [ ] Boot elke node van NixOS minimal ISO
- [ ] `bash scripts/collect-hardware-info.sh 10.0.20.1X` draaien
- [ ] NIC interface naam verifiëren (eno1 of anders?)
- [ ] Disk device naam verifiëren (/dev/sda of /dev/nvme0n1?)
- [ ] Interfaces en disk invullen in `hosts/nodeX/default.nix` en `modules/disk-config.nix`
- [ ] flannel-iface updaten in `modules/k3s-server-init.nix`

### Fase 4 — Nodes deployen — OPEN
- [ ] `bash scripts/deploy-node.sh node1` (wist disk!)
- [ ] Wachten: K3s API bereikbaar op 10.0.20.11:6443
- [ ] kubeconfig kopiëren: `scp root@10.0.20.11:/etc/rancher/k3s/k3s.yaml ~/.kube/config`
- [ ] `bash scripts/deploy-node.sh node2`
- [ ] `bash scripts/deploy-node.sh node3`
- [ ] `kubectl get nodes` → alle 3 Ready

### Fase 5 — Node age keys registreren — OPEN
- [ ] Per node: `ssh root@10.0.20.1X "cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age"`
- [ ] Pubkeys invullen in `.sops.yaml`
- [ ] `sops secrets/secrets.yaml` opnieuw encrypten (nu met alle 4 keys)

### Fase 6 — K8s Secrets aanmaken — OPEN
- [ ] `bash scripts/create-k8s-secrets.sh`
  Maakt aan: cloudflare-api-token, ghost-secrets, pelican-secrets, romm-secrets,
  shelf-secrets, silverbullet-secrets, vaultwarden-secrets

### Fase 7 — ArgoCD bootstrappen — OPEN
- [ ] `bash scripts/bootstrap-argocd.sh`
- [ ] Sync-waves monitoren: `kubectl -n argocd get applications -w`
- [ ] Volgorde: Kyverno → MetalLB → Traefik → cert-manager → Longhorn → alle apps

### Fase 8 — TrueNAS SCALE configureren — OPEN
- [ ] Dataset + NFS share: `datapool/longhorn-backup` (hosts: .11, .12, .13)
- [ ] Dataset + NFS share: `datapool/media` (read-only voor .11, .12, .13)
- [ ] Dataset + NFS share: `datapool/roms` (hosts: .11, .12, .13)

### Fase 9 — DNS records aanmaken — OPEN
- [ ] In Cloudflare: A-record `daviddelporte.com` → publiek IP
- [ ] In Cloudflare: A-record `*.daviddelporte.com` → publiek IP (wildcard)
- [ ] Port forwarding op UniFi: extern 443 → 10.0.20.100:443
  (80 is niet nodig bij DNS-01 challenge)

### Fase 10 — TLS verificatie — OPEN
- [ ] `kubectl get certificate -A` → alle READY: True (staging certs)
- [ ] Browser: check "niet vertrouwd staging cert" ✅
- [ ] Wildcard cert aanpassen in `apps/cert-manager/wildcard-certificate.yaml`:
  `letsencrypt-staging` → `letsencrypt-prod`
- [ ] Push → cert-manager vraagt prod wildcard cert aan

### Fase 11 — Post-hardening — OPEN
- [ ] Vaultwarden ADMIN_TOKEN disablen na eerste setup
- [ ] Grafana wachtwoord wijzigen (staat op "changeme")
- [ ] Renovate GitHub PAT instellen in repo Actions secrets
- [ ] Uptime Kuma monitors instellen voor alle services
- [ ] Longhorn recurring snapshots instellen (daily-snapshot, retain 7)

---

## 11. Openstaande TODO's in de codebase

| Bestand | TODO |
|---------|------|
| `hosts/*/default.nix` | SSH authorized keys toevoegen |
| `hosts/*/default.nix` | NIC interface naam verifiëren na hardware boot |
| `modules/disk-config.nix` | Disk device naam verifiëren (/dev/sda vs nvme) |
| `modules/k3s-server-init.nix` | flannel-iface verifiëren |
| `.sops.yaml` | Echte age pubkeys invullen (workstation + nodes) |
| `secrets/secrets.yaml` | Alle waarden invullen + encrypten |
| `apps/monitoring/application.yaml` | Grafana wachtwoord via sops (staat op "changeme") |
| `apps/vaultwarden/manifests/deployment.yaml` | SMTP configureren (optioneel) |
| `apps/ghost/manifests/deployment.yaml` | SMTP configureren (optioneel) |
| `apps/longhorn/application.yaml` | NFS backup target activeren na TrueNAS setup |

---

## 12. Kritieke valkuilen

1. **Longhorn crasht op NixOS** → Kyverno fix vereist (`infrastructure/kyverno-longhorn-fix.yaml`) — al aanwezig
2. **K3s token nooit inline** → altijd via `tokenFile` (Nix store is world-readable) — al correct
3. **UDP 8472 open** → Flannel VXLAN voor pod DNS (`common/default.nix`) — al ingesteld
4. **ArgoCD v3 apply** → `kubectl apply --server-side --force-conflicts` (anders veld-conflicts)
5. **LF line endings** → CRLF laat `nix eval` crashen (CI checkt dit)
6. **Staging vóór prod** → nooit direct `letsencrypt-prod` bij eerste deploy (rate limits)
7. **Kyverno vóór Longhorn** → sync-wave -5 vs -1 — al correct geconfigureerd
8. **etcd v1.34+** → vereist etcd 3.5.26 (check K3s release notes bij upgrades)

---

## 13. GitHub issues status

| # | Titel | Status |
|---|-------|--------|
| #2 | Phase 1: Hardware info verzamelen | Open — wacht op fysieke nodes |
| #3 | Phase 2: Age keys + secrets encrypten | Open — deels nu al te doen |
| #4 | Phase 3: Domein instellen | **Deels klaar** — domein daviddelporte.com ingevuld |
| #5 | Phase 4: flake.lock + nodes deployen | Open — wacht op hardware |
| #6 | Phase 5: ArgoCD bootstrappen | Open — wacht op hardware |
| #7 | TrueNAS NFS shares aanmaken | Open — wacht op hardware |
| #8 | Image versies pinnen | **Gesloten ✅** |
| #9 | K8s Secret resources aanmaken | **Gesloten ✅** |
| #10 | Epic: Bootstrap/Deployment | Open — tracking |
| #11 | Definition of Done Phase 5 | Open — tracking |

---

## 14. Recente wijzigingen

**2026-03-18:**
- Domein ingesteld: `daviddelporte.com` (alle manifests bijgewerkt)
- cert-manager omgezet van HTTP-01 naar DNS-01 via Cloudflare
- Wildcard cert toegevoegd: `*.daviddelporte.com`
- Cloudflare API token toegevoegd aan `secrets/secrets.yaml` template en bootstrap script
- `docs/project-summary.md` aangemaakt

**2026-03-17:**
- PR #12 gemerged: image versies gepind, CI sops-check gefixed, alerting rules, Traefik middleware
- Issue #8 gesloten
- K8s Secret templates aangemaakt per app + `scripts/create-k8s-secrets.sh`
- `.sops.yaml` gerefactored (YAML anchor)
- Issue #9 gesloten
- Alle 14 ingresses gecorrigeerd van `letsencrypt-prod` → `letsencrypt-staging`
- `docs/cert-manager-tls.md` aangemaakt
