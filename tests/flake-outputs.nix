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
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ "x86_64-linux" "aarch64-linux" ];
          modules = [
            ({ system, ... }: { packages.foo = "foo-${system}"; })
            ({ ... }: { nixosModules.mod-a = "a"; })
            ({ ... }: { nixosModules.mod-b = "b"; })
          ];
        };
      in
      {
        mods = result.nixosModules;
        pkgX86 = result.packages.x86_64-linux.foo;
        pkgArm = result.packages.aarch64-linux.foo;
      };
    expected = {
      mods = { mod-a = "a"; mod-b = "b"; };
      pkgX86 = "foo-x86_64-linux";
      pkgArm = "foo-aarch64-linux";
    };
  };

  # System-dependent module must not produce flake-scoped output.
  testMixedPerSystemAndFlakeThrows = {
    expr = throws (
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
            ({ system, ... }: {
              packages.hello = "hello-${system}";
              nixosModules.mymod = "my-mod";
            })
          ];
        };
      in
      result.nixosModules.mymod
    );
    expected = true;
  };

  # withSystem in modules and in the flake parameter both work with self'.
  testWithSystem = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          self = result;
          perSystem = { ... }: { packages.default = "my-pkg"; };
          modules = [
            ({ withSystem, ... }: {
              nixosConfigurations.from-module = withSystem sys ({ self', ... }:
                self'.packages.default);
            })
          ];
          flake = { withSystem }: {
            nixosConfigurations.from-flake = withSystem sys ({ system, ... }: system);
          };
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

  # Module flake outputs merge with `flake` parameter; collisions throw.
  testFlakeMergeAndCollisions = {
    expr =
      let
        merged = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [ ({ ... }: { nixosModules.from-module = "module-val"; }) ];
          flake = { nixosModules.from-flake = "flake-val"; };
        };
      in
      {
        merge = merged.nixosModules;
        collisionFlake = throws (lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [ ({ ... }: { nixosModules.x = "a"; }) ];
          flake = { nixosModules.x = "b"; };
        }).nixosModules.x;
        collisionModules = throws (lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
            ({ ... }: { nixosModules.x = "a"; })
            ({ ... }: { nixosModules.x = "b"; })
          ];
        }).nixosModules.x;
      };
    expected = {
      merge = { from-module = "module-val"; from-flake = "flake-val"; };
      collisionFlake = true;
      collisionModules = true;
    };
  };

  # Module declaring a custom flake-scoped category via outputs.
  testCustomFlakeScopedCategory = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
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
