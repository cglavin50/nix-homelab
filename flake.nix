{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    colmena.url = "github:zhaofengli/colmena";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    colmena,
    sops-nix,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
  in {
    # Development shell output
    devShells.${system}.default = pkgs.mkShell {
      packages = [
        colmena.packages.${system}.colmena
        pkgs.sops
        pkgs.age
        pkgs.ssh-to-age

        # k8s
        pkgs.kubectl
        pkgs.fluxcd
        pkgs.helm

        # formating/linting
        pkgs.pre-commit
        pkgs.gitleaks
        pkgs.alejandra
        pkgs.statix

        # misc
        pkgs.openssl # key/token generation
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

        specialArgs = {
          inherit sops-nix; # make sops-nix available to all nodes
          # secretsPath = "./nodes/secrets/k3s-token.yaml";
        };
      };

      defaults = {...}: {
        imports = [
          ./nodes/configuration.nix
          sops-nix.nixosModules.sops # give all attributes sops access
        ];

        # define sops config and k3s-token secret
        sops = {
          age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
          secrets.k3s-token = {
            sopsFile = ./secrets/k3s-token.yaml;
          };
        };
      };

      alpha = import ./nodes/alpha.nix;
      bravo = import ./nodes/bravo.nix;
      charlie = import ./nodes/charlie.nix;
    };
  };
}
