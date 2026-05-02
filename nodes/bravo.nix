{config, ...}: {
  imports = [
    ./hardware/bravo-hardware.nix
    ./k3s-config.nix
  ];

  networking = {
    hostName = "bravo";
    interfaces.eno2.ipv4.addresses = [
      {
        address = "10.0.0.60";
        prefixLength = 24;
      }
    ];
  };

  deployment = {
    targetHost = "10.0.0.60";
    targetUser = "cooper";
  };

  services.k3s = {
    enable = true;
    role = "server";
    tokenFile = config.sops.secrets.k3s-token.path;
    serverAddr = "https://10.0.0.50:6443";
  };
}
