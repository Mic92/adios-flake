# Tests for tree construction with mixed module types
let
  prelude = import ./prelude.nix;
  inherit (prelude) lib types nixpkgs sys;

  throws = expr:
    let result = builtins.tryEval (builtins.deepSeq expr expr);
    in !result.success;
in
{
  # Mixed module types in one tree
  mixedModules = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
            # Ergonomic function (system-dependent)
            ({ pkgs, ... }: { packages.fn-pkg = "fn"; })
            # Native adios module
            { name = "native"; inputs.nixpkgs = { path = "/nixpkgs"; }; impl = { inputs, ... }: { packages.native-pkg = inputs.nixpkgs.system; }; }
            # Static attrset
            { packages.static-pkg = "static"; }
          ];
        };
      in
      result.packages.${sys};
    expected = {
      fn-pkg = "fn";
      native-pkg = sys;
      static-pkg = "static";
    };
  };

  # perSystem + modules combined
  perSystemAndModules = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          perSystem = { pkgs, ... }: { packages.from-perSystem = "ps"; };
          modules = [
            ({ pkgs, ... }: { packages.from-modules = "mod"; })
          ];
        };
      in
      result.packages.${sys};
    expected = {
      from-perSystem = "ps";
      from-modules = "mod";
    };
  };

  # Config options wired correctly
  configOptions = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
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
  multipleCategories = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
            ({ pkgs, ... }: { packages.pkg1 = "p1"; })
            ({ pkgs, ... }: { checks.chk1 = "c1"; })
            ({ pkgs, ... }: { devShells.default = "ds"; })
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
  flakeAndPerSystem = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
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
