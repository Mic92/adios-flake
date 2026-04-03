# Tests for module classification: options-only module, full module, perSystem closures, edge cases
let
  prelude = import ./prelude.nix;
  inherit (prelude) lib nixpkgs sys;

  # Helper to build and get packages for currentSystem
  mkAndGetPkgs = mod: (lib.mkFlake { inputs = { inherit nixpkgs; }; }
    ({ systems = [ sys ]; } // mod)).packages.${sys};

  # Helper: does evaluation throw?
  throws = expr:
    let
      result = builtins.tryEval (builtins.deepSeq expr expr);
    in
    !result.success;
in
{
  # 1. Options-only native module needs the explicit `_type = "adiosModule"`
  # marker since `options` is also a flake-parts module key.
  testOptionsOnlyModule = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ sys ];
          imports = [
            { _type = "adiosModule"; name = "settings"; options.debug = { type = prelude.types.bool; default = false; }; }
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
      imports = [
        {
          name = "full";
          inputs.nixpkgs = { path = "/nixpkgs"; };
          impl = { inputs, ... }: { packages.sys = inputs.nixpkgs.system; };
        }
      ];
    };
    expected = { sys = sys; };
  };

  # 3. perSystem closure (system-dependent)
  testPerSystemSysDep = {
    expr = mkAndGetPkgs {
      perSystem = { pkgs, system, ... }: { packages.sys-info = system; };
    };
    expected = { sys-info = sys; };
  };

  # 4. perSystem closure asking for no per-system args — engine memoizes
  testPerSystemPure = {
    expr = mkAndGetPkgs {
      perSystem = { ... }: { packages.meta = "v1"; };
    };
    expected = { meta = "v1"; };
  };

  # 5. Duplicate native module name detection
  testDuplicateNameThrows = {
    expr = throws (lib.mkFlake { inputs = { inherit nixpkgs; }; } {
      systems = [ sys ];
      imports = [
        { name = "dup"; impl = { ... }: { packages.a = "a"; }; }
        { name = "dup"; impl = { ... }: { packages.b = "b"; }; }
      ];
    });
    expected = true;
  };

  # 6. Mixed: named native + anonymous perSystem closures
  testMixedNaming = {
    expr = mkAndGetPkgs {
      imports = [
        { name = "named"; impl = { ... }: { packages.named = "named-val"; }; }
        { perSystem = { pkgs, ... }: { packages.anon = "anon-val"; }; }
      ];
    };
    expected = { named = "named-val"; anon = "anon-val"; };
  };
}
