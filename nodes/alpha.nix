{config, ...}: {
  imports = [
    ./hardware/alpha-hardware.nix
    ./k3s-config.nix
  ];

  networking = {
    hostName = "alpha";
    interfaces.eno2.ipv4.addresses = [
      {
        address = "192.168.1.50";
        prefixLength = 24;
      }
    ];
  };

  # alpha will serve as our subnet router
  services.tailscale = {
    useRoutingFeatures = "server";
    extraUpFlags = [
      "--advertise-routes=192.168.1.0/24" # make sure to approve in the UI
    ];
  };

  deployment = {
    targetHost = "192.168.1.50";
    targetUser = "cooper";
  };

  services.k3s = {
    enable = true;
    role = "server";
    tokenFile = config.sops.secrets.k3s-token.path;
    clusterInit = true;

    extraFlags = toString [
      # configure TLS ip/magicdns name for remote api access
      "--tls-san=100.74.55.105"
      "--tls-san=alpha"
    ];
  };
}
