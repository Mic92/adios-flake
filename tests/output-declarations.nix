# Tests for collectOutputDeclarations: default-only, module extending defaults,
# conflicting declarations, consistent redeclarations
let
  prelude = import ./prelude.nix;
  inherit (prelude) lib nixpkgs sys;

  throws = expr:
    let result = builtins.tryEval (builtins.deepSeq expr expr);
    in !result.success;
in
{
  # Conflicting declarations should throw
  testConflictingDeclarationsThrow = {
    expr = throws (lib.mkFlake {
      inputs = { nixpkgs = nixpkgs; };
      systems = [ sys ];
      modules = [
        {
          name = "mod-a";
          outputs = { foo = { type = "attrset"; }; };
          impl = { ... }: { foo.x = "a"; };
        }
        {
          name = "mod-b";
          outputs = { foo = { type = "scalar"; }; };
          impl = { ... }: { foo = "b"; };
        }
      ];
    });
    expected = true;
  };

  # Consistent redeclarations are allowed
  testConsistentRedeclarations = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
            {
              name = "mod-a";
              outputs = { packages = { type = "attrset"; }; };
              impl = { ... }: { packages.from-a = "a"; };
            }
            {
              name = "mod-b";
              outputs = { packages = { type = "attrset"; }; };
              impl = { ... }: { packages.from-b = "b"; };
            }
          ];
        };
      in
      result.packages.${sys};
    expected = { from-a = "a"; from-b = "b"; };
  };

  # Module redeclaring a default category consistently works
  testRedeclareDefaultCategory = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
            {
              name = "checker";
              outputs = { checks = { type = "attrset"; }; };
              impl = { ... }: { checks.my-check = "ok"; };
            }
          ];
        };
      in
      result.checks.${sys}.my-check;
    expected = "ok";
  };
}
