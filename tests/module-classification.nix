# Tests for module classification: options-only module, full module, static attrset, function, edge cases
let
  prelude = import ./prelude.nix;
  inherit (prelude) lib nixpkgs sys;

  # Helper to build and get packages for currentSystem
  mkAndGetPkgs = args: (lib.mkFlake ({
    inputs = { nixpkgs = nixpkgs; };
    systems = [ sys ];
  } // args)).packages.${sys};

  # Helper: does evaluation throw?
  throws = expr:
    let
      result = builtins.tryEval (builtins.deepSeq expr expr);
    in
    !result.success;
in
{
  # 1. Options-only native module is classified as native (has structural key "options")
  testOptionsOnlyModule = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
            # This has "options" structural key → native adios module
            { name = "settings"; options.debug = { type = prelude.types.bool; default = false; }; }
            # A module that reads options from settings
            { name = "reader"; inputs.settings = { path = "/settings"; }; impl = { inputs, ... }: { packages.debug-val = builtins.toJSON inputs.settings.debug; }; }
          ];
        };
      in
      result.packages.${sys}.debug-val;
    expected = "false";
  };

  # 2. Full native module (options + inputs + impl)
  testFullNativeModule = {
    expr = mkAndGetPkgs {
      modules = [
        {
          name = "full";
          inputs.nixpkgs = { path = "/nixpkgs"; };
          impl = { inputs, ... }: { packages.sys = inputs.nixpkgs.system; };
        }
      ];
    };
    expected = { sys = sys; };
  };

  # 3. Static attrset is normalized
  testStaticAttrset = {
    expr = mkAndGetPkgs {
      modules = [
        { packages.foo = "static-val"; }
      ];
    };
    expected = { foo = "static-val"; };
  };

  # 4. Ergonomic function (system-dependent)
  testErgonomicFnSysDep = {
    expr = mkAndGetPkgs {
      modules = [
        ({ pkgs, system, ... }: { packages.sys-info = system; })
      ];
    };
    expected = { sys-info = sys; };
  };

  # 5. Ergonomic function (system-independent)
  testErgonomicFnPure = {
    expr = mkAndGetPkgs {
      modules = [
        ({ ... }: { packages.meta = "v1"; })
      ];
    };
    expected = { meta = "v1"; };
  };

  # 6. Edge case: attrset with only "modules" key is treated as native
  testModulesOnlyNative = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
            {
              name = "parent";
              modules.child = {
                impl = { ... }: { packages.from-child = "child-val"; };
              };
            }
          ];
        };
      in
      # Parent module has no impl, so no result.
      # But the module is classified as native (has "modules" key).
      # This test ensures no error occurs.
      builtins.attrNames result;
    expected = [];
  };

  # 7. Duplicate name detection
  testDuplicateNameThrows = {
    expr = throws (lib.mkFlake {
      inputs = { nixpkgs = nixpkgs; };
      systems = [ sys ];
      modules = [
        { name = "dup"; impl = { ... }: { packages.a = "a"; }; }
        { name = "dup"; impl = { ... }: { packages.b = "b"; }; }
      ];
    });
    expected = true;
  };

  # 8. Mixed named + anonymous modules
  testMixedNaming = {
    expr = mkAndGetPkgs {
      modules = [
        { name = "named"; impl = { ... }: { packages.named = "named-val"; }; }
        ({ pkgs, ... }: { packages.anon = "anon-val"; })
        { packages.static = "static-val"; }
      ];
    };
    expected = { named = "named-val"; anon = "anon-val"; static = "static-val"; };
  };
}
