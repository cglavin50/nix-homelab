{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    colmena.url = "github:zhaofengli/colmena";
  };

  outputs = {
    nixpkgs,
    colmena,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
  in {
    # Development shell output
    devShells.${system}.default = pkgs.mkShell {
      packages = [
        colmena.packages.${system}.colmena
        pkgs.kubectl
      ];

      shellHook = ''
        echo "K3s cluster development environment loaded!"
      '';
    };

    # Colmena configuration output
    colmenaHive = colmena.lib.makeHive {
      meta = {
        nixpkgs = import nixpkgs {
          system = "x86_64-linux";
          overlays = [];
        };
      };

      defaults = import ./nodes/configuration.nix;
      alpha = import ./nodes/alpha.nix;
      bravo = import ./nodes/bravo.nix;
      charlie = import ./nodes/charlie.nix;
    };
  };
}
