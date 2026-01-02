_: {
  # k3s firewall rules
  networking.firewall = {
    allowedTCPPorts = [
      6443 # k3s API communication
      2379 # etcd clients
      2380 # etcd peers
      10250 # metrics-server
    ];
    allowedUDPPorts = [
      8472 # k3s, flannel
    ];

    # tailscale config
    trustedInterfaces = ["tailscale0"];
    interfaces.tailscale0 = {
      allowedTCPPorts = [6443];
    };
  };
}
