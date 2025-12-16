{...}: {
  # k3s firewall rules
  networking.firewall.allowedTCPPorts = [
    6443 # k3s API communication
    2379 # etcd clients
    2380 # etcd peers
  ];
  networking.firewall.allowedUDPPorts = [
    8472 # k3s, flannel
  ];
}
