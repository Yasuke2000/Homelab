# Pre-deployment Hardware Checklist — Architect Prompt

Gebruik deze prompt om Claude (architect mode) te vragen alles na te lopen
voordat je nodes deployt. Kopieer alles hieronder en plak het in een nieuw gesprek.

---

## PROMPT (kopieer hieronder)

---

Ik heb een bare-metal NixOS homelab klaar voor deployment. Ik wil dat jij als
architect alle openstaande hardware-informatie met me doorloopt zodat we de repo
compleet kunnen maken voordat we deployen.

### Context

**Repo**: https://github.com/Yasuke2000/Homelab (branch: master)

**Stack**: NixOS 25.05, K3s HA (embedded etcd), ArgoCD v3, Longhorn, Traefik v3,
cert-manager, MetalLB, Kyverno, sops-nix + age

**3 nodes — allemaal klaar voor boot:**

| Node | Hardware | IP | Rol |
|------|----------|----|-----|
| node1 | HP ProDesk 400 G7 SFF, i7-10700, 16 GB | 10.0.20.11 | K3s cluster-init (etcd leader) |
| node2 | HP EliteDesk 800 G5 Mini, i5-9500T, 16 GB | 10.0.20.12 | K3s server-join |
| node3 | HP EliteDesk 800 G6 Mini, i5-10500, 16 GB | 10.0.20.13 | K3s server-join |

**NAS**: Synology DS918+, IP 10.0.20.14, NFS shares: longhorn-backup, media, roms

**Netwerk**: UniFi Cloud Gateway Ultra (10.0.20.1) + Pro Max 16 switch, VLAN 20 (10.0.20.0/24)

**Ventoy USB**: klaar met NixOS 25.05 minimal ISO

### Wat nog ingevuld moet worden in de repo (per node)

In `hosts/nodeX/default.nix` staan nog twee TODO's die pas ingevuld kunnen
worden nadat we de node gebooot hebben van de Ventoy USB:

```nix
homelab.node.mac  = "TODO_REPLACE_WITH_MAC";   -- MAC-adres van de LAN NIC
homelab.node.disk = "TODO_REPLACE_WITH_DISK";  -- /dev/nvme0n1 of /dev/sda etc.
```

We hebben een script klaar dat dit automatisch uitprint:
```bash
bash scripts/collect-hardware-info.sh nodeX
```
Dit script runt op de live ISO en print MAC, disk device, NIC naam, etc.

### Wat ik van jou wil

Loop met mij door de volgende punten — stel per punt gerichte vragen als er
informatie mist, of bevestig als alles klopt:

**1. BIOS-instellingen (per node)**
- Secure Boot: moet UIT staan
- After Power Loss / AC Power Recovery: moet op "Power On" staan (voor UPS-reboot)
- Boot order: USB eerst
- Heb jij dit al gecontroleerd op node1, node2, node3?

**2. Hardware discovery (per node)**
- Zijn de MAC-adressen en disk device names al bekend?
- Zo nee: plan is om van Ventoy USB te booten en `collect-hardware-info.sh` te draaien
- Uitvoer per node opslaan als `node-info-node1.txt` etc.
- Daarna invullen in `hosts/node1/default.nix`, `hosts/node2/default.nix`, `hosts/node3/default.nix`

**3. Synology DS918+ NAS**
- DSM geïnstalleerd? IP 10.0.20.14 ingesteld?
- NFS shares aangemaakt: `longhorn-backup`, `media`, `roms`?
- NFS permissions: `10.0.20.0/24`, `rw`, `no_root_squash`?
- WD Red 3TB in bay 4 geplaatst?

**4. Netwerk**
- Cloud Gateway Ultra uitgerold? VLAN 20 aangemaakt (10.0.20.0/24)?
- DHCP pool op VLAN 20 zodat nodes tijdelijk een IP krijgen voor deploy?
- Pro Max 16 switch geadopteerd?
- Alle nodes en NAS aangesloten op switch?

**5. Deployment readiness check**
- `smart-deploy.sh` verwacht een tijdelijk DHCP-IP als eerste argument
  (`bash scripts/smart-deploy.sh <dhcp-ip> node1 server-init`)
- Weet je hoe je het DHCP-IP van een node achterhaal? (UniFi dashboard of
  `arp-scan` / `nmap -sn 10.0.20.0/24` na boot)

**6. Post-deploy: age keys voor sops**
- Na eerste boot van elke node moet je het SSH host key converteren naar een
  age public key en toevoegen aan `.sops.yaml`:
  ```bash
  ssh root@10.0.20.11 'nix-shell -p ssh-to-age --run \
    "ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub"'
  ```
- Daarna: `sops updatekeys secrets/secrets.yaml` op je workstation
- Is dit al voorbereid/begrepen?

### Deployment volgorde (ter referentie)

```
Phase 1: nodes provisionen
  bash scripts/smart-deploy.sh <dhcp-ip> node1 server-init   # altijd eerst
  bash scripts/smart-deploy.sh <dhcp-ip> node2 server-join
  bash scripts/smart-deploy.sh <dhcp-ip> node3 server-join

Phase 2: ArgoCD bootstrap
  bash scripts/bootstrap-argocd.sh

Phase 3: Synology NFS (handmatig via DSM)

Phase 4: TLS staging → prod
  grep -rl "letsencrypt-staging" apps/ | xargs sed -i 's/letsencrypt-staging/letsencrypt-prod/g'
  git add apps/ && git commit -m "feat: switch to letsencrypt-prod" && git push
```

### Mijn vraag

Welke van bovenstaande punten zijn nog niet klaar? Vraag me per punt de status
en help me een concreet actieplan maken voor wat er nog moet gebeuren voordat
`smart-deploy.sh` voor node1 kan draaien.

---
