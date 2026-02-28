# Regression tests for scalar per-system outputs (e.g. formatter)
#
# The flake schema expects `formatter.${system}` to be a single derivation,
# not an attrset of named entries.  The collector/transpose must handle this
# without decomposing the derivation into its attribute names.
let
  prelude = import ./prelude.nix;
  inherit (prelude) lib nixpkgs sys;

in
{
  # A module that returns a scalar (non-attrset) value for a per-system
  # output category.  After transposition the value must arrive intact.
  testScalarOutput = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          perSystem = { pkgs, ... }: {
            formatter = "my-formatter";
          };
        };
      in
      result.formatter.${sys};
    expected = "my-formatter";
  };

  # Scalar outputs across multiple systems stay per-system.
  testScalarMultiSystem = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ "x86_64-linux" "aarch64-linux" ];
          perSystem = { system, ... }: {
            formatter = "fmt-${system}";
          };
        };
      in
      result.formatter;
    expected = {
      x86_64-linux = "fmt-x86_64-linux";
      aarch64-linux = "fmt-aarch64-linux";
    };
  };

  # Mix of scalar and attrset categories from the same module.
  testScalarMixedWithAttrset = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          perSystem = { pkgs, ... }: {
            formatter = "my-fmt";
            packages.hello = "hello-pkg";
          };
        };
      in
      {
        fmt = result.formatter.${sys};
        pkg = result.packages.${sys}.hello;
      };
    expected = {
      fmt = "my-fmt";
      pkg = "hello-pkg";
    };
  };

  # NOTE: scalar/attrset type conflicts between modules for the same category
  # are NOT detected eagerly.  The collector merges lazily with // to avoid
  # forcing values that may reference `self` (which would cause infinite
  # recursion).  If two modules set the same category to different types,
  # the result is undefined and will error at access time.
}
