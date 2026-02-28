# Tests for transposition: single category, multiple categories, category present in subset of systems
let
  prelude = import ./prelude.nix;
  inherit (prelude) lib nixpkgs;
  systems = [ "x86_64-linux" "aarch64-linux" ];
in
{
  # Single category, multiple systems
  testSingleCategory = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          inherit systems;
          modules = [
            ({ system, ... }: { packages.foo = "foo-${system}"; })
          ];
        };
      in
      result.packages;
    expected = {
      x86_64-linux.foo = "foo-x86_64-linux";
      aarch64-linux.foo = "foo-aarch64-linux";
    };
  };

  # Multiple categories
  testMultipleCategories = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          inherit systems;
          modules = [
            ({ system, ... }: { packages.foo = "pkg-${system}"; checks.bar = "chk-${system}"; })
          ];
        };
      in
      {
        pkgs = result.packages;
        chks = result.checks;
      };
    expected = {
      pkgs = {
        x86_64-linux.foo = "pkg-x86_64-linux";
        aarch64-linux.foo = "pkg-aarch64-linux";
      };
      chks = {
        x86_64-linux.bar = "chk-x86_64-linux";
        aarch64-linux.bar = "chk-aarch64-linux";
      };
    };
  };

  # Category present in subset of systems (conditional output)
  testCategorySubset = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          inherit systems;
          modules = [
            ({ system, ... }:
              { packages.foo = "foo-${system}"; }
              // (if system == "x86_64-linux"
                  then { checks.linux-only = "linux-check"; }
                  else {})
            )
          ];
        };
      in
      {
        pkgs = result.packages;
        chks = result.checks;
      };
    expected = {
      pkgs = {
        x86_64-linux.foo = "foo-x86_64-linux";
        aarch64-linux.foo = "foo-aarch64-linux";
      };
      chks = {
        x86_64-linux.linux-only = "linux-check";
        aarch64-linux = {};
      };
    };
  };
}
