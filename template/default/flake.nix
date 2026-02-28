{
  description = "Description for the project";

  inputs = {
    adios-flake.url = "github:hercules-ci/adios-flake";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs@{ adios-flake, self, ... }:
    adios-flake.lib.mkFlake {
      inherit inputs self;
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      perSystem = { pkgs, system, ... }: {
        # Per-system attributes can be defined here. The system argument
        # provides the current system string.

        packages.default = pkgs.hello;
      };
      flake = {
        # System-agnostic flake attributes can be defined here,
        # such as nixosModules, overlays, etc.
      };
    };
}
