# Tests for tree construction with mixed module types
let
  prelude = import ./prelude.nix;
  inherit (prelude) lib types nixpkgs sys;

  throws = expr:
    let result = builtins.tryEval (builtins.deepSeq expr expr);
    in !result.success;
in
{
  # perSystem + imports combined
  testPerSystemAndImports = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ sys ];
          perSystem = { pkgs, ... }: { packages.from-perSystem = "ps"; };
          imports = [
            { perSystem = { pkgs, ... }: { packages.from-import = "mod"; }; }
          ];
        };
      in
      result.packages.${sys};
    expected = {
      from-perSystem = "ps";
      from-import = "mod";
    };
  };

  # Config options wired correctly
  testConfigOptions = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ sys ];
          imports = [
            {
              name = "mymod";
              options.greeting = { type = types.string; default = "hello"; };
              impl = { options, ... }: { packages.greet = options.greeting; };
            }
          ];
          config.mymod = { greeting = "bonjour"; };
        };
      in
      result.packages.${sys}.greet;
    expected = "bonjour";
  };

  # Multiple categories from different modules
  testMultipleCategories = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ sys ];
          imports = [
            { perSystem = { pkgs, ... }: { packages.pkg1 = "p1"; }; }
            { perSystem = { pkgs, ... }: { checks.chk1 = "c1"; }; }
            { perSystem = { pkgs, ... }: { devShells.default = "ds"; }; }
          ];
        };
      in
      {
        pkg = result.packages.${sys}.pkg1;
        chk = result.checks.${sys}.chk1;
        shell = result.devShells.${sys}.default;
      };
    expected = { pkg = "p1"; chk = "c1"; shell = "ds"; };
  };

  # flake attrset merging with perSystem
  testFlakeAndPerSystem = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ sys ];
          perSystem = { pkgs, ... }: { packages.hello = "hello"; };
          flake = { nixosModules.default = "mod"; };
        };
      in
      {
        pkg = result.packages.${sys}.hello;
        mod = result.nixosModules.default;
      };
    expected = { pkg = "hello"; mod = "mod"; };
  };
}
