# Test: scalar `formatter` output from one module produces correct
# `formatter.<system>` shape
let
  prelude = import ./prelude.nix;
  inherit (prelude) lib nixpkgs;
  systems = [ "x86_64-linux" "aarch64-linux" ];
in
{
  # Scalar formatter from a native module with outputs declaration
  testScalarFormatterShape = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          inherit systems;
          modules = [
            {
              name = "treefmt";
              outputs = { formatter = { type = "scalar"; }; };
              inputs.nixpkgs = { path = "/nixpkgs"; };
              impl = { inputs, ... }: {
                formatter = "fmt-${inputs.nixpkgs.system}";
              };
            }
          ];
        };
      in
      result.formatter;
    expected = {
      x86_64-linux = "fmt-x86_64-linux";
      aarch64-linux = "fmt-aarch64-linux";
    };
  };

}
