{
  description = "Description for the project";

  inputs = {
    adios-flake.url = "github:hercules-ci/adios-flake";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs@{ adios-flake, self, ... }:
    adios-flake.lib.mkFlake {
      inherit inputs self;
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      modules = [
        # Import additional modules
        (import ./hello/flake-module.nix)
      ];
      perSystem = { pkgs, inputs', ... }: {
        # Per-system attributes can be defined here. The inputs'
        # parameter provides easy access to per-system inputs.

        packages.figlet = inputs'.nixpkgs.figlet;
      };
      flake = {
        # System-agnostic flake attributes can be defined here,
        # such as nixosModules, overlays, etc.
      };
    };
}
