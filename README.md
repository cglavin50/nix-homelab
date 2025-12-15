# Nix-Homelab

This repository hosts the configuration for my nixos-based homelab running k3s. Currently, I am running this on 3x Lenovo M920q ThinkCentre nodes (256GB nvme storage, 16gb DDR4 ram, i-8500T).

## Initial Configuration

Each machine was flashed with NixOS, with basic SSH and user configured. Then, [Colmena](https://github.com/zhaofengli/colmena) was used to configure each machine with the appropriate dependencies.
