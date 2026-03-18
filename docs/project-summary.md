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

**Status hardware**: Nodes zijn nog NIET fysiek beschikbaar. Repo is volledig klaar voor deploy.

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
| kube-prom-stack | 70.4.2           | prometheus-community     | Prometheus + Grafana + Alertmanager|
| sops-nix        | follows nixpkgs  | n/a                      | Secrets decryptie op NixOS boot   |

---

## 4. Domein & TLS

- **Domein**: `daviddelporte.com` (bij Cloudflare)
- **Email**: `admin@daviddelporte.com`
- **TLS methode**: DNS-01 via Cloudflare API (geen port forwarding nodig)
- **Certificaat type**: wildcard `*.daviddelporte.com`
- **Huidige issuer**: `letsencrypt-staging` (overstap naar prod na verificatie)

### Subdomains per service

| Service | Subdomain |
|---------|-----------|
| Ghost (website) | daviddelporte.com |
| ArgoCD | argocd.daviddelporte.com |
| Grafana | grafana.daviddelporte.com |
| Vaultwarden | vault.daviddelporte.com |
| Actual Budget | budget.daviddelporte.com |
| Homepage | home.daviddelporte.com |
| Jellyfin | jellyfin.daviddelporte.com |
| Jellyseerr | requests.daviddelporte.com |
| Pelican | games.daviddelporte.com |
| RomM | romm.daviddelporte.com |
| Shelf | shelf.daviddelporte.com |
| SilverBullet | notes.daviddelporte.com |
| Longhorn UI | longhorn.daviddelporte.com |

---

## 5. Secrets beheer — VOLLEDIG KLAAR ✅

### Age encryptie
- **Methode**: age (asymmetrisch, geen GPG)
- **Workstation pubkey**: `age1m483x92dqmkazqx8xu7xc8waw3uh23a890uv4tcj6d4xafg98alqq0vqeh`
- **Private key locatie**: `C:\Users\DavidD\.config\sops\age\keys.txt`
- **Backup**: private GitHub repo `Yasuke2000/homelab-secrets`
- **Node keys**: worden toegevoegd NA eerste node deploy (issue #16)

### secrets/secrets.yaml — volledig geëncrypt ✅
Alle velden zijn aanwezig en versleuteld met AES256_GCM:

| Veld | Status |
|------|--------|
| k3s.token | ✅ Encrypted |
| vaultwarden.adminToken | ✅ Encrypted |
| vaultwarden.smtpUsername | ✅ Encrypted |
| vaultwarden.smtpPassword | ✅ Encrypted |
| ghost.dbPassword | ✅ Encrypted |
| silverbullet.password | ✅ Encrypted |
| shelf.sessionSecret | ✅ Encrypted |
| romm.dbPassword | ✅ Encrypted |
| romm.secretKey | ✅ Encrypted |
| pelican.dbPassword | ✅ Encrypted |
| actualBudget.password | ✅ Encrypted |
| grafana.adminPassword | ✅ Encrypted |
| cloudflare.apiToken | ✅ Encrypted |

**Opmerking**: `renovate.githubToken` is NIET aanwezig — Renovate draait als GitHub App en heeft geen PAT nodig. Dit veld is bewust verwijderd.

### App Kubernetes Secrets — volledig geëncrypt ✅

| Bestand | Status |
|---------|--------|
| apps/vaultwarden/manifests/secret.yaml | ✅ Encrypted |
| apps/ghost/manifests/secret.yaml | ✅ Encrypted |
| apps/silverbullet/manifests/secret.yaml | ✅ Encrypted |
| apps/shelf/manifests/secret.yaml | ✅ Encrypted |
| apps/romm/manifests/secret.yaml | ✅ Encrypted |
| apps/pelican/manifests/secret.yaml | ✅ Encrypted |
| apps/monitoring/manifests/secret.yaml | ✅ Encrypted (grafana-admin-secret) |

---

## 6. CI/CD pipeline — VOLLEDIG GROEN ✅

Elke push op master triggert 5 checks — alle slagen:

| Check | Status |
|-------|--------|
| nix flake check | ✅ Passing |
| yaml-lint | ✅ Passing |
| kubeconform | ✅ Passing |
| sops-check + trufflehog | ✅ Passing |
| line-endings (LF only) | ✅ Passing |

**Geïnstalleerde GitHub-apps**: Renovate (GitHub App), CodeRabbit, Codacy

---

## 7. Deployment checklist — huidige status

### ✅ KLAAR (geen hardware nodig)
- [x] Repository op GitHub (Yasuke2000/Homelab, branch: master)
- [x] Alle NixOS configs (flake, modules, hosts, common)
- [x] Alle Kubernetes manifests (18 apps, 15 namespaces)
- [x] Image versies gepind (geen :latest)
- [x] CI pipeline groen (5/5 checks)
- [x] Scripts (deploy, bootstrap, hardware-info)
- [x] Domein: daviddelporte.com via Cloudflare DNS-01
- [x] cert-manager: DNS-01, wildcard *.daviddelporte.com
- [x] Alle ingresses op letsencrypt-staging
- [x] SSH keys (PC + telefoon) in common/default.nix
- [x] Age key gegenereerd, .sops.yaml geconfigureerd
- [x] secrets/secrets.yaml volledig ingevuld en geëncrypt
- [x] Alle app K8s Secret manifests geëncrypt
- [x] Grafana wachtwoord via existingSecret (niet hardcoded)
- [x] Alerting rules (Prometheus)
- [x] GitHub issues aangemaakt (#14 t/m #18)

### ⏳ WACHT OP HARDWARE (issues #14–#18)

**Issue #14 — Fase 2 (VOLGENDE STAP):**
- [ ] Boot elke HP EliteDesk van NixOS minimal ISO
- [ ] Boot elke HP EliteDesk van NixOS minimal ISO (Ventoy USB)
- [ ] Run `bash scripts/smart-deploy.sh <temp-ip> nodeX server-init/join`
- [ ] Script detecteert automatisch MAC + disk + genereert age keys

**Issue #15 — Fase 3:**
- [ ] `bash scripts/smart-deploy.sh <temp-ip> node1/2/3 server-init/join`
- [ ] Alle 3 nodes Ready in `kubectl get nodes`

**Issue #16 — Fase 4:**
- [ ] Node age keys ophalen en toevoegen aan .sops.yaml
- [ ] `sops updatekeys` op alle encrypted bestanden

**Issue #17 — Fase 5:**
- [ ] TrueNAS NFS shares aanmaken (longhorn-backup, roms, media)
- [ ] `bash scripts/bootstrap-argocd.sh`
- [ ] `kubectl apply -f apps/app-of-apps.yaml`

**Issue #18 — Fase 6:**
- [ ] Verifieer staging certs (kubectl get certificate -A)
- [ ] Switch naar letsencrypt-prod
- [ ] Alertmanager receiver instellen
- [ ] Uptime Kuma monitors instellen
- [ ] Longhorn recurring snapshots

---

## 8. Kritieke valkuilen

1. **Longhorn crasht op NixOS** → Kyverno fix vereist (`infrastructure/kyverno-longhorn-fix.yaml`) — aanwezig
2. **K3s token nooit inline** → altijd via `tokenFile` (sops) — correct
3. **UDP 8472 open** → Flannel VXLAN — ingesteld in common/default.nix
4. **ArgoCD v3** → `kubectl apply --server-side --force-conflicts`
5. **openiscsi** (geen hyphen) in nixpkgs environment.systemPackages
6. **.sops.yaml indentatie** → age recipients op 10 spaties (niet 8)
7. **Grafana** → via `existingSecret: grafana-admin-secret`, niet inline
8. **LF only** in .nix/.yaml/.sh, CI checkt dit
9. **Staging vóór prod** → nooit direct letsencrypt-prod bij eerste deploy
10. **NIC naam** → verifiëren met collect-hardware-info.sh (default `eno1`, kan afwijken)

---

## 9. Recentste wijzigingen (2026-03-18)

- Age key vervangen: WSL2 distro was weg, nieuwe key gegenereerd op Windows
- Alle secrets encrypted: k3s, vaultwarden (incl. SMTP), cloudflare, grafana, alle app DB passwords
- Alle app K8s Secret manifests encrypted met sops
- Grafana wachtwoord: hardcoded "changeme" vervangen door existingSecret referentie
- renovate.githubToken: verwijderd (GitHub App, geen PAT nodig)
- CI gefixed: openiscsi, .sops.yaml indentatie, prune: spacing in 20 bestanden
- CLAUDE.md bijgewerkt met actuele status en nieuwe gotchas
- GitHub issues #14–#18 aangemaakt per fase
- Age key backup: private repo Yasuke2000/homelab-secrets
