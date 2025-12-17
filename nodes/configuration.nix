{pkgs, ...}: {
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "America/New_York";

  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    keyMap = "us";
    font = "Lat2-Terminus16";
  };

  # networking/ssh
  networking = {
    networkmanager.enable = true;
    firewall.enable = true;
    nameservers = ["8.8.8.8"];
    defaultGateway = "192.168.1.1";
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # TODO: create a dedicated deploy user
  nix.settings.trusted-users = ["root" "cooper"];
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false; # TODO: remove this, just in place to get initial configs applied
  };

  users.users.cooper = {
    isNormalUser = true;
    extraGroups = ["wheel"]; # enable sudo
    packages = with pkgs; [
      tree
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMYdi2EMa78x4zBtFUAjyGOZpGnhNlfHmxShfevsmxL4 cooper@nixos-btw"
    ];
  };

  environment.systemPackages = with pkgs; [
    neovim
    vim
    git
  ];
}
