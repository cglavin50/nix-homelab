# Nix-Homelab

This repository hosts the configuration for my nixos-based homelab running k3s. Currently, I am running this on 3x Lenovo M920q ThinkCentre nodes (256GB nvme storage, 16gb DDR4 ram, i-8500T). The root `flake.nix` also configures a developer shell, adding `colmena`, `sops`, and `age` for nixos-management.

**Credit:** This project is heavily inspired by [Dreams of Autonomy](https://www.youtube.com/@dreamsofautonomy) - specifically the [youtube video](https://www.youtube.com/watch?v=2yplBzPCghA&t=315s) and corresponding [repo](https://github.com/dreamsofautonomy/homelab/tree/main).

## Initial Configuration

Each machine was flashed with NixOS, with basic SSH and user configured. Then, [Colmena](https://github.com/zhaofengli/colmena) was used to configure each machine with the appropriate dependencies.

### Bootstrapping

For colmena to apply, the following configurations need to be manually applied on each node:

**Valid Network Connection (Nameserver, Default Gateway):**

```
networking.defaultGateway = "192.168.1.1" # replace with appropriate value
networking.nameservers = [ "8.8.8.8" ]; # replace with desired DNS server
```

This can also be done via the cli for initial scaffolding: 

```
sudo ip route add default via 192.168.1.1
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

**Elevated Permissions:**

The target user needs to be able to push untrusted packages, as well as `sudo` without password

```
security.sudo = {
  enable = true;
  wheelNeedsPassword = false;
};
nix.settings.trusted-users = [ "root" "cooper" ]; # replace with your user
```

## K3s

This homelab follows the [nix k3s usage guide](https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/networking/cluster/k3s/docs/USAGE.md#multi-node) for a 3-node HA cluster.

Secret management is configured with [sops](https://github.com/Mic92/sops-nix), using [age](https://github.com/FiloSottile/age) for encryption. 

### FluxCD

This repository implements [FluxCD](https://fluxcd.io/) for a GitOps-based approach (read more [here](https://www.gitops.tech/#what-is-gitops)).

Initial bootstrapping is done with:
`lux bootstrap github --owner=cglavin50 --repository=nix-homelab --branch=main --personal --path=k8s`(requires kubectl to be configured)
