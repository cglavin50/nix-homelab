{config, ...}: {
  imports = [
    ./hardware/charlie-hardware.nix
    ./k3s-config.nix
  ];

  networking = {
    hostName = "charlie";
    interfaces.eno2.ipv4.addresses = [
      {
        address = "192.168.1.70";
        prefixLength = 24;
      }
    ];
  };

  deployment = {
    targetHost = "192.168.1.70";
    targetUser = "cooper";
  };

  services.k3s = {
    enable = true;
    role = "server";
    tokenFile = config.sops.secrets.k3s-token.path;
    serverAddr = "https://192.168.1.50:6443";
  };
}
