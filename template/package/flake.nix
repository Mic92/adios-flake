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
      perSystem = { pkgs, ... }:
        let
          hello = pkgs.callPackage ./hello/package.nix { };
        in
        {
          packages.default = hello;
          packages.hello = hello;

          checks.hello = pkgs.callPackage ./hello/test.nix {
            inherit hello;
          };
        };
    };
}
