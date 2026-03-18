# Hardware & Cost

This homelab runs on four refurbished HP EliteDesk 800 G4 Mini PCs — silent,
power-efficient enterprise desktops that are purpose-built for 24/7 operation
and widely available as corporate lease returns.

---

## Hardware overview

| Node | Role | IP |
|------|------|----|
| node1 | K3s cluster-init (etcd leader) | 10.0.20.11 |
| node2 | K3s control-plane | 10.0.20.12 |
| node3 | K3s control-plane | 10.0.20.13 |
| nas | TrueNAS SCALE (NFS storage) | 10.0.20.14 |

All four are **HP EliteDesk 800 G4 Mini** — same hardware, different roles.

### Why this machine?

- **Ultra-small form factor** — fits on a shelf, no rack needed
- **Low power draw** — ~10–25W per unit under normal load
- **Near-silent** — single small fan, rarely audible
- **Enterprise-grade NIC** — Intel i219LM, excellent Linux/NixOS support
- **Easy to upgrade** — M.2 NVMe slot + 2.5" SATA + 2× SO-DIMM slots
- **Widely available refurbished** — corporate lease returns, readily found second-hand

### Specs per node

| Component | Spec |
|-----------|------|
| CPU | Intel Core i5-8500T (8th gen, 6-core, 35W TDP) |
| RAM | 16 GB DDR4 SO-DIMM |
| Storage (nodes 1–3) | NVMe SSD for NixOS + Longhorn replica |
| Storage (NAS) | NVMe for TrueNAS OS + HDDs/SSDs for data pool |
| Network | 1 GbE Intel i219LM |
| OS (nodes 1–3) | NixOS 25.05 |
| OS (NAS) | TrueNAS SCALE |

---

## Cost breakdown

### One-time costs

The biggest cost driver is the hardware itself. Refurbished HP EliteDesk 800 G4 Mini
units are broadly available on Marktplaats, eBay, and certified refurbished dealers.

| Category | What you need |
|----------|--------------|
| 4× HP EliteDesk 800 G4 Mini | The nodes themselves |
| RAM upgrades (if base config is 8 GB) | DDR4 SO-DIMM kits |
| NVMe SSDs for the three K3s nodes | OS + Longhorn storage |
| NVMe SSD + data drives for TrueNAS | OS drive + storage pool |
| USB stick for Ventoy provisioning | Any 32 GB+ USB stick |

**Software is entirely free**: NixOS, K3s, ArgoCD, Longhorn, Traefik, cert-manager,
Grafana, and all self-hosted apps are open source. Let's Encrypt TLS certificates
are free. Cloudflare DNS and proxying are free.

The only ongoing paid service is the domain registration (~€10/year).

### Recurring costs

| Cost | Amount |
|------|--------|
| Electricity (4 nodes, 24/7, ~€0.30/kWh) | ~€15–20/month |
| Domain renewal | ~€10/year |
| Everything else | €0 |

**Total ongoing: roughly €15–20/month**, almost entirely electricity.

Power draw estimate: four EliteDesks at light load average ~20W each = 80W total.
At typical Belgian electricity rates that works out to €15–20/month.

---

## Homelab vs cloud

Running the same workload on managed cloud infrastructure:

| | This homelab | Cloud equivalent |
|--|-------------|-----------------|
| **Setup cost** | Hardware purchase (one-time) | €0 |
| **Monthly cost** | ~€17 (electricity + domain) | €80–200+ |
| **Break-even** | 6–12 months | — |
| **After 3 years** | Hardware + ~€600 running costs | €2 900–7 200 |
| **Data sovereignty** | Full — nothing leaves home | Vendor-controlled |
| **Learning depth** | Hardware, OS, networking, K8s | Managed services only |

A rough cloud equivalent (3-node Kubernetes + NAS-equivalent storage + domain):

- **AWS EKS**: 3× `t3.medium` + EBS + Route53 — €100–150/month
- **Hetzner** (cheapest viable): 3× CX21 + volumes — €25–40/month
- **GKE Autopilot**: €80–130/month depending on usage

The homelab pays for itself within the first year compared to even the cheapest
cloud option, while giving you full control and better hardware specs.

---

## Network setup

The homelab runs on a dedicated VLAN (`VLAN 20`, `10.0.20.0/24`) managed by
a UniFi gateway at `10.0.20.1`.

| Subnet | Purpose |
|--------|---------|
| `10.0.20.0/24` | Homelab VLAN — all nodes + services |
| `10.0.20.1` | UniFi gateway / DNS |
| `10.0.20.11–13` | K3s control-plane nodes |
| `10.0.20.14` | TrueNAS NAS |
| `10.0.20.100–200` | MetalLB LoadBalancer pool |
| `10.0.20.100` | Traefik (fixed assignment) |

VLAN isolation keeps homelab traffic separate from the home LAN. All external
traffic enters through Cloudflare → Traefik at `10.0.20.100`.

---

## Where to source the hardware

| Source | Notes |
|--------|-------|
| **Marktplaats.nl** | Best prices in the Netherlands/Belgium |
| **eBay.nl / eBay.de** | Wide selection, filter by "refurbished" |
| **Azerty.nl / Alternate.nl** | Certified refurbished, warranty included |
| **Amazon.de** — "Renewed" | 90-day return policy |
| **Local IT recyclers** | Often cheapest, no warranty |

Search for **"HP EliteDesk 800 G4 Mini i5"**. Avoid G1/G2 (too old). G3 works
but G4 has better NIC support on NixOS and slightly better power efficiency.

---

## Optional additions

| Item | Why |
|------|-----|
| Small UPS (e.g. APC Back-UPS 600VA) | Protects etcd during power cuts — gives ~10 min to graceful shutdown |
| Smart plug (energy monitoring) | Track per-device power and remotely power-cycle stuck nodes |
| Extra NVMe for TrueNAS | Expand NAS storage without replacing the machine |
