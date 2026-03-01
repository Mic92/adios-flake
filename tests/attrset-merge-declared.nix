# Tests for attrset merge with declared categories:
# confirm existing collision detection still works when categories are
# explicitly declared via outputs.
let
  prelude = import ./prelude.nix;
  inherit (prelude) lib nixpkgs sys;

  throws = expr:
    let result = builtins.tryEval (builtins.deepSeq expr expr);
    in !result.success;
in
{
  # Two modules with overlapping keys in a declared attrset category throw
  testDeclaredAttrsetCollision = {
    expr = throws (lib.mkFlake {
      inputs = { nixpkgs = nixpkgs; };
      systems = [ sys ];
      modules = [
        {
          name = "mod-a";
          outputs = { packages = { type = "attrset"; }; };
          impl = { ... }: { packages.foo = "a"; };
        }
        {
          name = "mod-b";
          outputs = { packages = { type = "attrset"; }; };
          impl = { ... }: { packages.foo = "b"; };
        }
      ];
    }).packages.${sys}.foo;
    expected = true;
  };

  # Custom declared attrset category with collision detection
  testCustomAttrsetCollision = {
    expr = throws (lib.mkFlake {
      inputs = { nixpkgs = nixpkgs; };
      systems = [ sys ];
      modules = [
        {
          name = "mod-a";
          outputs = { containers = { type = "attrset"; }; };
          impl = { ... }: { containers.web = "a"; };
        }
        {
          name = "mod-b";
          outputs = { containers = { type = "attrset"; }; };
          impl = { ... }: { containers.web = "b"; };
        }
      ];
    }).containers.${sys}.web;
    expected = true;
  };
}
