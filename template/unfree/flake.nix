{
  description = "Description for the project";

  inputs = {
    adios-flake.url = "github:hercules-ci/adios-flake";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs@{ adios-flake, nixpkgs, self, ... }:
    adios-flake.lib.mkFlake {
      inherit inputs self;
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      perSystem = { system, ... }:
        let
          # Import nixpkgs with allowUnfree
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        {
          packages.default = pkgs.hello-unfree;
        };
    };
}
