let
  prelude = import ./prelude.nix;
  inherit (prelude) lib types adiosLib nixpkgs sys;

  throws = expr:
    let result = builtins.tryEval (builtins.deepSeq expr expr);
    in !result.success;
in
{
  # Flake-scoped keys are not transposed; per-system keys are.
  # Multiple modules contributing different keys to the same category merge.
  testFlakeAndPerSystemRouting = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ "x86_64-linux" "aarch64-linux" ];
          imports = [
            { perSystem = { system, ... }: { packages.foo = "foo-${system}"; }; }
            { flake.nixosModules.mod-a = "a"; }
            { flake.nixosModules.mod-b = "b"; }
            { flake.modules.nixos.server = "srv"; }
          ];
        };
      in
      {
        mods = result.nixosModules;
        modHierarchy = result.modules;
        pkgX86 = result.packages.x86_64-linux.foo;
        pkgArm = result.packages.aarch64-linux.foo;
      };
    expected = {
      mods = { mod-a = "a"; mod-b = "b"; };
      modHierarchy = { nixos.server = "srv"; };
      pkgX86 = "foo-x86_64-linux";
      pkgArm = "foo-aarch64-linux";
    };
  };

  # withSystem available to top-level module functions for flake-scoped outputs.
  testWithSystem = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; self = result; }; } {
          systems = [ sys ];
          perSystem = { ... }: { packages.default = "my-pkg"; };
          imports = [
            ({ withSystem, ... }: {
              flake.nixosConfigurations.from-module = withSystem sys ({ self', ... }:
                self'.packages.default);
            })
            ({ withSystem, ... }: {
              flake.nixosConfigurations.from-flake = withSystem sys ({ system, ... }: system);
            })
          ];
        };
      in
      {
        fromModule = result.nixosConfigurations.from-module;
        fromFlake = result.nixosConfigurations.from-flake;
      };
    expected = {
      fromModule = "my-pkg";
      fromFlake = sys;
    };
  };

  # `flake.*` from multiple imports deep-merges; perSystem collisions still throw.
  testFlakeMergeAndCollisions = {
    expr =
      let
        merged = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ sys ];
          imports = [
            { flake.nixosModules.from-module = "module-val"; }
            { flake.modules.nixos.from-module = "mod-val"; }
          ];
          flake = {
            nixosModules.from-flake = "flake-val";
            modules.home.from-flake = "home-val";
          };
        };
      in
      {
        merge = merged.nixosModules;
        modMerge = merged.modules;
        collisionPerSystem = throws (lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ sys ];
          imports = [
            { perSystem = { ... }: { packages.x = "a"; }; }
            { perSystem = { ... }: { packages.x = "b"; }; }
          ];
        }).packages.${sys}.x;
      };
    expected = {
      merge = { from-module = "module-val"; from-flake = "flake-val"; };
      modMerge = { nixos.from-module = "mod-val"; home.from-flake = "home-val"; };
      collisionPerSystem = true;
    };
  };

  # Module declaring a custom flake-scoped category via outputs.
  testCustomFlakeScopedCategory = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ sys ];
          imports = [
            {
              name = "container-mod";
              outputs = { containers = { type = "attrset"; scope = "flake"; }; };
              impl = { ... }: { containers.web = "web-container"; };
            }
          ];
        };
      in
      result.containers.web;
    expected = "web-container";
  };
}
