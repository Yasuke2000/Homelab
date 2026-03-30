{ config, pkgs, lib, ... }:

{
  # ---------------------------------------------------------------------------
  # NixOS 25.05 – Shared baseline for all K3s nodes
  # ---------------------------------------------------------------------------

  # Boot: systemd-boot + EFI (disko lays out the ESP partition)
  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ---------------------------------------------------------------------------
  # Networking baseline
  # ---------------------------------------------------------------------------
  networking = {
    # Static DNS (gateway + Cloudflare fallback)
    nameservers = [ "10.0.20.1" "1.1.1.1" ];

    # Firewall: default deny-in, selective allow
    firewall = {
      enable = true;

      # K3s control-plane API
      allowedTCPPorts = [
        6443   # Kubernetes API server
        2379   # etcd client
        2380   # etcd peer
        10250  # kubelet API (metrics-server, kubectl logs/exec)
      ];

      # Flannel VXLAN – CRITICAL: without UDP 8472 pod DNS is broken
      # See: gotchas.md #3
      allowedUDPPorts = [
        8472   # Flannel VXLAN overlay
      ];
    };
  };

  # ---------------------------------------------------------------------------
  # Time & locale
  # ---------------------------------------------------------------------------
  time.timeZone            = "Europe/Brussels";
  i18n.defaultLocale       = "en_US.UTF-8";
  console.keyMap           = "be-latin1";

  # ---------------------------------------------------------------------------
  # SSH hardening
  # Note: NixOS option names are case-sensitive — PasswordAuthentication
  # NOT passwordAuthentication. See: gotchas.md #7
  # ---------------------------------------------------------------------------
  services.openssh = {
    enable = true;

    settings = {
      PasswordAuthentication = false;   # key-only login
      PermitRootLogin        = "prohibit-password";  # keys only, needed for nixos-rebuild --target-host
      X11Forwarding          = false;
    };
  };

  # ---------------------------------------------------------------------------
  # Users — admin + root SSH keys (PC and phone)
  # ---------------------------------------------------------------------------
  users.users.admin = {
    isNormalUser = true;
    extraGroups  = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGBNjGpptYwOI0mHX7z1LeUoOFVRWQxw3KvyY0wt1YHB homelab-admin-pc"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKaLz9nbBy/IjEbnpBipuGWGKtoFEkcDrVX8NrwYX291 homelab-admin-phone"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINHwlPiaC+iv48TXBXXNrvwfqnKko9C4ryP9oP0wZraG homelab-admin-workstation"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICTGSJxf77pWPjijfJUhPbfDXGlYKtCrFohdOLm6X89Q homelab-admin-werk-laptop"
    ];
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGBNjGpptYwOI0mHX7z1LeUoOFVRWQxw3KvyY0wt1YHB homelab-admin-pc"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKaLz9nbBy/IjEbnpBipuGWGKtoFEkcDrVX8NrwYX291 homelab-admin-phone"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINHwlPiaC+iv48TXBXXNrvwfqnKko9C4ryP9oP0wZraG homelab-admin-workstation"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICTGSJxf77pWPjijfJUhPbfDXGlYKtCrFohdOLm6X89Q homelab-admin-werk-laptop"
  ];

  # ---------------------------------------------------------------------------
  # Base packages present on every node
  # ---------------------------------------------------------------------------
  environment.systemPackages = with pkgs; [
    # Essential CLI tools
    curl
    wget
    git
    vim
    htop
    jq
    yq-go

    # K8s / cluster tooling
    kubectl
    kubernetes-helm
    k9s

    # Diagnostics
    tcpdump
    nmap
    iotop
    lsof

    # Storage helpers (Longhorn needs these on the host)
    nfs-utils
    openiscsi
  ];

  # ---------------------------------------------------------------------------
  # iSCSI daemon – required by Longhorn for block storage
  # ---------------------------------------------------------------------------
  services.openiscsi = {
    enable     = true;
    name       = "iqn.2025-01.homelab:${config.networking.hostName}";
  };

  # ---------------------------------------------------------------------------
  # NFS client support – for TrueNAS SCALE mounts
  # ---------------------------------------------------------------------------
  services.rpcbind.enable = true;

  # ---------------------------------------------------------------------------
  # Kernel modules needed by Longhorn / K3s
  # ---------------------------------------------------------------------------
  boot.kernelModules = [
    "iscsi_tcp"   # Longhorn block storage
    "dm_snapshot" # volume snapshots
    "dm_thin_pool"
    "overlay"     # container overlay fs
    "br_netfilter" # required for K8s networking
  ];

  boot.kernel.sysctl = {
    "net.bridge.bridge-nf-call-iptables"  = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.ipv4.ip_forward"                 = 1;
  };

  # ---------------------------------------------------------------------------
  # sops-nix: global age key path (per-node key lives at this path on disk)
  # The actual key is provisioned by nixos-anywhere during first deploy
  # ---------------------------------------------------------------------------
  # Derive age key from SSH host key (pre-generated by smart-deploy.sh via nixos-anywhere --extra-files).
  # The node age public key is added to .sops.yaml before deploy, so secrets decrypt on first boot.
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # ---------------------------------------------------------------------------
  # Nix daemon settings
  # ---------------------------------------------------------------------------
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store   = true;

      # Binary cache substituters (speeds up rebuilds)
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCUSPs4="
      ];
    };

    # Automatic GC: keep last 7 days, run weekly
    gc = {
      automatic = true;
      dates     = "weekly";
      options   = "--delete-older-than 7d";
    };
  };

  # NixOS release – must match the channel you're tracking
  system.stateVersion = "25.05";
}
