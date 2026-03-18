# Node Provisioning Guide

Fully automated bare-metal provisioning using `smart-deploy.sh`.

## Overview

The provisioning flow for any new node:

```
Boot installer (DHCP) → smart-deploy.sh → discovers MAC + disk
  → patches hosts/<node>/default.nix
  → generates SSH host key + age key
  → adds age key to .sops.yaml + re-encrypts secrets
  → commits to git
  → nixos-anywhere deploy (wipes disk, installs NixOS)
  → waits for node on static IP
  → verifies K3s cluster membership
```

## Node roles

| Nodes   | Role         | Module               | etcd | API server | Workload |
|---------|--------------|----------------------|------|------------|----------|
| node1   | server-init  | k3s-server-init.nix  | yes  | yes        | yes      |
| node2-6 | server-join  | k3s-server-join.nix  | yes  | yes        | yes      |
| node7-9 | worker       | k3s-worker.nix       | no   | no         | yes      |

## IP allocation

| Node   | IP           | VLAN 20              |
|--------|-------------|----------------------|
| node1  | 10.0.20.11  | etcd leader          |
| node2  | 10.0.20.12  | control-plane        |
| node3  | 10.0.20.13  | control-plane        |
| node4  | 10.0.20.14  | expansion slot       |
| node5  | 10.0.20.15  | expansion slot       |
| node6  | 10.0.20.16  | expansion slot       |
| node7  | 10.0.20.17  | dedicated worker     |
| node8  | 10.0.20.18  | dedicated worker     |
| node9  | 10.0.20.19  | dedicated worker     |

## USB preparation (Ventoy)

The provisioning USB uses [Ventoy](https://ventoy.net) — one USB, multiple ISOs, no re-flashing.

### Install Ventoy on the USB (Windows)

1. Download Ventoy from https://github.com/ventoy/Ventoy/releases (latest)
2. Run `Ventoy2Disk.exe`, select your USB drive (drive D:), click Install
3. Rename the main Ventoy partition to `HOMELAB` (right-click in Explorer → Rename)

### Add NixOS 25.05 minimal ISO

Download the NixOS 25.05 minimal ISO and copy it to the Ventoy partition:

```
ISO URL:
https://channels.nixos.org/nixos-25.05/latest-nixos-minimal-x86_64-linux.iso

# Or with curl (Git Bash):
curl -L -o D:/nixos-minimal-25.05-x86_64-linux.iso \
  https://channels.nixos.org/nixos-25.05/latest-nixos-minimal-x86_64-linux.iso
```

Verify the SHA-256 hash from https://channels.nixos.org/nixos-25.05/ before booting.

### Boot from Ventoy

1. Insert USB, boot node (F9 or F12 for boot menu on HP EliteDesk)
2. Select the USB drive in BIOS boot menu
3. Ventoy menu appears → select `nixos-minimal-25.05-x86_64-linux.iso`
4. At NixOS boot prompt, wait for `nixos@nixos:~$`
5. Note the DHCP IP: `ip addr show | grep 'inet '`
6. Verify SSH works: `ssh root@<dhcp-ip>` (no password needed on NixOS installer)

### HP EliteDesk 800 G4 BIOS settings

Before first boot, verify these BIOS settings (F10 at startup):
- Secure Boot: **Disabled** (NixOS installer won't boot with Secure Boot)
- Boot Mode: **UEFI** (not Legacy/CSM)
- Wake on LAN: **Enabled** (optional, useful for remote management)

## Prerequisites

```bash
# Enter dev shell (provides all tools)
nix develop

# Verify tools are available
ssh-to-age --version
sops --version
nixos-anywhere --version
```

## Deploying a new node

### Step 1 — Boot installer

Boot the node from NixOS minimal ISO (USB or PXE). Ensure DHCP gives it a
temporary IP. Note that IP.

### Step 2 — Run smart-deploy.sh

```bash
# First node (cluster-init)
bash scripts/smart-deploy.sh 192.168.1.50 node1 server-init

# Additional control-plane nodes
bash scripts/smart-deploy.sh 192.168.1.51 node2 server-join
bash scripts/smart-deploy.sh 192.168.1.52 node3 server-join

# Worker nodes
bash scripts/smart-deploy.sh 192.168.1.53 node7 worker
```

The script handles everything automatically:
- Discovers MAC address and primary disk via SSH
- Patches `hosts/<node>/default.nix` with real values
- Pre-generates SSH host key so the node age key is known before deploy
- Adds node age key to `.sops.yaml` and re-encrypts `secrets/secrets.yaml`
- Commits changes to git
- Deploys via nixos-anywhere (wipes disk)
- Waits for node on its static IP
- Verifies cluster membership

### Step 3 — Verify

```bash
# After node1
ssh root@10.0.20.11 kubectl get nodes

# After all nodes
bash scripts/health-check.sh
bash scripts/health-check.sh --full  # also checks etcd, Longhorn, ArgoCD
```

## Manual MAC/disk discovery (alternative)

If you prefer to collect hardware info separately before running smart-deploy.sh:

```bash
# From the booted installer
ssh root@<temp-ip>

# Discover MAC
ip link show | grep -A1 "state UP" | grep "link/ether" | awk '{print $2}'

# Discover primary disk
lsblk -dpno NAME,SIZE | grep -v 'loop\|sr' | sort -k2 -hr | head -1

# Then edit hosts/<node>/default.nix manually
```

## nixos-facter (alpha)

nixos-facter can auto-generate hardware configs. It's alpha software — useful
for discovery but don't rely on it for production configs. The MAC-based
networking approach in `modules/networking.nix` is more reliable.

```bash
# Optional hardware discovery tool (alpha)
nix run github:numtide/nixos-facter -- --output facter.json
```

## Networking architecture

NIC matching uses MAC addresses via systemd-networkd (`modules/networking.nix`).
This is interface-name agnostic — works whether the NIC shows as `eno1`, `enp3s0`,
`eth0`, etc. No need to know the NIC name before deployment.

K3s `--flannel-iface` is intentionally omitted — K3s auto-detects the correct
interface from the `--node-ip` routing table.

## Gotchas

### K3s token immutability
The K3s cluster token (`k3s/token` in secrets.yaml) is baked into etcd at
cluster init. **Never change it after the cluster is bootstrapped.** Changing
it requires full cluster rebuild.

### systemd-networkd vs networking.interfaces
Never mix `networking.interfaces` with `networking.useNetworkd = true`. These
conflict. Use only `systemd.network.networks` when networkd is enabled.

### nixos-facter alpha warning
nixos-facter is useful for hardware discovery but should not replace
hand-written configs for production. Its output format may change.

## Upgrading nodes

```bash
# Rolling upgrade (updates flake.lock, upgrades one node at a time)
bash scripts/upgrade-cluster.sh

# Dry run first
bash scripts/upgrade-cluster.sh --dry-run
```

Upgrade order: workers → control-plane → etcd leader (node1 last).
Each node is verified Ready before proceeding to the next.
On failure, the failed node is automatically rolled back.

## Adding a new node type

1. Choose a slot (node4-9) from `hosts/`
2. Pick the appropriate module: `k3s-server-join.nix` or `k3s-worker.nix`
3. Assign an IP from 10.0.20.14-19
4. Run `smart-deploy.sh` — it handles the rest
