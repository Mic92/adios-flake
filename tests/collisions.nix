# Tests for collision detection in the merge/transpose/flake-merge layers
let
  prelude = import ./prelude.nix;
  inherit (prelude) lib nixpkgs sys;

  throws = expr:
    let result = builtins.tryEval (builtins.deepSeq expr expr);
    in !result.success;
in
{
  # Two modules setting the same key within the same category should throw
  testModuleKeyCollision = {
    expr = throws (lib.mkFlake {
      inputs = { nixpkgs = nixpkgs; };
      systems = [ sys ];
      modules = [
        ({ ... }: { checks.foo = "from-module-a"; })
        ({ ... }: { checks.foo = "from-module-b"; })
      ];
    }).checks.${sys}.foo;
    expected = true;
  };

  # Two modules setting different keys within the same category should NOT throw
  testModuleNoCollision = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
            ({ ... }: { checks.foo = "from-module-a"; })
            ({ ... }: { checks.bar = "from-module-b"; })
          ];
        };
      in
      result.checks.${sys};
    expected = {
      foo = "from-module-a";
      bar = "from-module-b";
    };
  };

  # flake attrs colliding with per-system transposed outputs should throw
  testFlakeVsPerSystemCollision = {
    expr = throws (lib.mkFlake {
      inputs = { nixpkgs = nixpkgs; };
      systems = [ sys ];
      modules = [
        ({ ... }: { checks.my-check = "from-module"; })
      ];
      flake = {
        checks.${sys}.my-check = "from-flake";
      };
    }).checks.${sys}.my-check;
    expected = true;
  };

  # flake attrs with non-overlapping keys should merge fine
  testFlakeVsPerSystemNoCollision = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
            ({ ... }: { checks.from-module = "module-val"; })
          ];
          flake = {
            checks.${sys}.from-flake = "flake-val";
          };
        };
      in
      result.checks.${sys};
    expected = {
      from-module = "module-val";
      from-flake = "flake-val";
    };
  };

  # flake attrs for a category not produced by any module should work
  testFlakeOnlyCategory = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
            ({ ... }: { packages.hello = "hello-pkg"; })
          ];
          flake = {
            nixosConfigurations.myhost = "myhost-config";
          };
        };
      in
      result.nixosConfigurations.myhost;
    expected = "myhost-config";
  };
}
