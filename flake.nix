{
  description = "Composable flake outputs using the adios module system";

  inputs = {
    adios.url = "github:adisbladis/adios";
  };

  outputs = inputs@{ adios, ... }:
    let
      lib = import ./lib.nix {
        inherit adios;
      };
      templates = {
        default = {
          path = ./template/default;
          description = ''
            A minimal flake using flake-parts.
          '';
        };
        multi-module = {
          path = ./template/multi-module;
          description = ''
            A flake with multiple modules.
          '';
        };
        package = {
          path = ./template/package;
          description = ''
            A flake with a simple package, callPackage, fileset src, and a check.
          '';
        };
        unfree = {
          path = ./template/unfree;
          description = ''
            A flake importing nixpkgs with the unfree option.
          '';
        };
      };
    in
    {
      inherit lib templates;
    };

}
