{
  name,
  nodes,
  pkgs,
  ...
}: {
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

  imports = [
    ./hardware/alpha-hardware.nix
  ];
}
