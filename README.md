# Nix-Homelab

This repository hosts the configuration for my nixos-based homelab running k3s. Currently, I am running this on 3x Lenovo M920q ThinkCentre nodes (256GB nvme storage, 16gb DDR4 ram, i-8500T).

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
