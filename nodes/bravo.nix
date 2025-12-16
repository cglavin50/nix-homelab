{
  name,
  nodes,
  pkgs,
  ...
}: {
  networking = {
    hostName = "bravo";
    interfaces.eno2.ipv4.addresses = [
      {
        address = "192.168.1.60";
        prefixLength = 24;
      }
    ];
  };

  deployment = {
    targetHost = "192.168.1.60";
    targetUser = "cooper";
  };

  imports = [
    ./hardware/bravo-hardware.nix
  ];
}
