{
  name,
  nodes,
  pkgs,
  ...
}: {
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
  imports = [
    ./hardware/charlie-hardware.nix
  ];
}
