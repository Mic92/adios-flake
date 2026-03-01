# Tests for scalar merge: one provider succeeds, two providers throws,
# zero providers omits category
let
  prelude = import ./prelude.nix;
  inherit (prelude) lib nixpkgs sys;

  throws = expr:
    let result = builtins.tryEval (builtins.deepSeq expr expr);
    in !result.success;
in
{
  # One module provides a scalar output — succeeds
  testScalarOneProvider = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
            {
              name = "fmt";
              outputs = { formatter = { type = "scalar"; }; };
              inputs.nixpkgs = { path = "/nixpkgs"; };
              impl = { inputs, ... }: { formatter = "my-formatter"; };
            }
          ];
        };
      in
      result.formatter.${sys};
    expected = "my-formatter";
  };

  # Two modules provide a scalar output — throws
  testScalarTwoProvidersThrows = {
    expr = throws (lib.mkFlake {
      inputs = { nixpkgs = nixpkgs; };
      systems = [ sys ];
      modules = [
        {
          name = "fmt-a";
          outputs = { formatter = { type = "scalar"; }; };
          impl = { ... }: { formatter = "fmt-a"; };
        }
        {
          name = "fmt-b";
          # No need to re-declare: formatter is already scalar by default
          impl = { ... }: { formatter = "fmt-b"; };
        }
      ];
    }).formatter.${sys};
    expected = true;
  };

  # Zero providers — category absent from output
  testScalarZeroProviders = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
            ({ pkgs, ... }: { packages.hello = "hello"; })
          ];
        };
      in
      result ? formatter;
    expected = false;
  };
}
