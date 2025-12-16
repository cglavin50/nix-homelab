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

  deployment = {
    targetHost = "192.168.1.50";
    targetUser = "cooper";
  };

  services.k3s = {
    enable = true;
    role = "server";
    tokenFile = config.sops.secrets.k3s-token.path;
    clusterInit = true;
  };
}
