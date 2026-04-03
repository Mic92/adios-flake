# Tests for flake-parts signature compatibility (issue #15)
#
# flake-parts uses a curried signature:
#   mkFlake { inherit inputs; } module
#
# where `module` is NixOS-module-style: a path, attrset, or function
# returning { systems, imports, perSystem, flake }.
#
# This lets users do:
#   inputs.jjui.inputs.flake-parts.follows = "adios-flake";
#
# We support the *shape* of the module (imports recursion, perSystem,
# flake merge) — not the full NixOS module system semantics
# (no priorities, no mkIf, no submodule options).
let
  prelude = import ./prelude.nix;
  inherit (prelude) lib nixpkgs sys;
in
{
  # Basic curried form: mkFlake { inputs } { systems; perSystem; }
  testCurriedBasic = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ sys ];
          perSystem = { pkgs, system, ... }: {
            packages.default = "hello-${system}";
          };
        };
      in
      result.packages.${sys}.default;
    expected = "hello-${sys}";
  };

  # Module as a function receiving { inputs, ... }
  testCurriedFunction = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } (
          { inputs, ... }: {
            systems = [ sys ];
            perSystem = { pkgs, ... }: {
              packages.hasNixpkgs = if inputs?nixpkgs then "yes" else "no";
            };
          }
        );
      in
      result.packages.${sys}.hasNixpkgs;
    expected = "yes";
  };

  # imports: multiple modules each contributing perSystem
  testCurriedImports = {
    expr =
      let
        modA = { ... }: {
          perSystem = { ... }: {
            packages.a = "from-a";
          };
        };
        modB = {
          perSystem = { system, ... }: {
            packages.b = "from-b-${system}";
          };
        };
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ sys ];
          imports = [ modA modB ];
          perSystem = { ... }: {
            packages.top = "from-top";
          };
        };
      in
      result.packages.${sys};
    expected = {
      a = "from-a";
      b = "from-b-${sys}";
      top = "from-top";
    };
  };

  # Nested imports (imports inside imports)
  testCurriedNestedImports = {
    expr =
      let
        leaf = { perSystem = { ... }: { packages.leaf = "leaf"; }; };
        mid = { imports = [ leaf ]; perSystem = { ... }: { packages.mid = "mid"; }; };
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ sys ];
          imports = [ mid ];
        };
      in
      result.packages.${sys};
    expected = { leaf = "leaf"; mid = "mid"; };
  };

  # flake.* outputs merged across imports
  testCurriedFlakeMerge = {
    expr =
      let
        modOverlay = { ... }: {
          flake.overlays.default = "overlay-fn";
        };
        modModule = {
          flake.nixosModules.foo = "nixos-mod";
        };
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ sys ];
          imports = [ modOverlay modModule ];
          flake.lib.greet = "hello";
        };
      in
      {
        overlay = result.overlays.default;
        nixosMod = result.nixosModules.foo;
        greet = result.lib.greet;
      };
    expected = {
      overlay = "overlay-fn";
      nixosMod = "nixos-mod";
      greet = "hello";
    };
  };

  # self resolution from inputs.self (flake-parts style)
  testCurriedSelfFromInputs = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; self = result; }; } {
          systems = [ sys ];
          perSystem = { self', ... }: {
            packages.a = "pkg-a";
            checks.ref = "got-${self'.packages.a}";
          };
        };
      in
      result.checks.${sys}.ref;
    expected = "got-pkg-a";
  };

  # Top-level module function receives self
  testCurriedSelfArg = {
    expr =
      let
        fakeSelf = { rev = "deadbeef"; };
        result = lib.mkFlake { inputs = { inherit nixpkgs; self = fakeSelf; }; } (
          { self, ... }: {
            systems = [ sys ];
            flake.rev = self.rev;
          }
        );
      in
      result.rev;
    expected = "deadbeef";
  };

  # Module as a path
  testCurriedPath = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ sys ];
          imports = [ ./fixtures/flake-parts-mod.nix ];
        };
      in
      result.packages.${sys}.fromFile;
    expected = "file-${sys}";
  };

  # withSystem available in top-level module functions
  testCurriedWithSystem = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; self = result; }; } (
          { withSystem, ... }: {
            systems = [ sys ];
            perSystem = { ... }: { packages.default = "pkg"; };
            flake.thing = withSystem sys ({ self', ... }: self'.packages.default);
          }
        );
      in
      result.thing;
    expected = "pkg";
  };
}
