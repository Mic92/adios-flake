# End-to-end integration tests
let
  prelude = import ./prelude.nix;
  inherit (prelude) lib types adiosLib nixpkgs sys;

  throws = expr:
    let result = builtins.tryEval (builtins.deepSeq expr expr);
    in !result.success;
in
{
  # 6.1 Simple flake-parts template equivalent
  testSimpleTemplate = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ "x86_64-linux" "aarch64-linux" ];
          perSystem = { pkgs, system, ... }: {
            packages.default = "hello-${system}";
          };
        };
      in
      {
        x86 = result.packages.x86_64-linux.default;
        aarch = result.packages.aarch64-linux.default;
      };
    expected = {
      x86 = "hello-x86_64-linux";
      aarch = "hello-aarch64-linux";
    };
  };

  # 6.2 Multiple module styles: perSystem closure + native adios module
  testMultipleModuleStyles = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ sys ];
          imports = [
            # perSystem closure (ergonomic function)
            { perSystem = { pkgs, ... }: { packages.from-fn = "fn-val"; }; }
            # Native adios module — passes straight through to the engine
            {
              name = "native";
              inputs.nixpkgs = { path = "/nixpkgs"; };
              impl = { inputs, ... }: { packages.from-native = inputs.nixpkgs.system; };
            }
          ];
        };
      in
      result.packages.${sys};
    expected = {
      from-fn = "fn-val";
      from-native = sys;
    };
  };

  # 6.3 Third-party module configuration via config parameter
  testThirdPartyConfig = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ sys ];
          imports = [
            {
              name = "treefmt";
              options.projectRootFile = { type = types.string; default = "default.nix"; };
              options.formatter = { type = types.string; default = "nixfmt"; };
              impl = { options, ... }: {
                packages.treefmt-config = "${options.projectRootFile}:${options.formatter}";
              };
            }
          ];
          config.treefmt = {
            projectRootFile = "flake.nix";
            formatter = "alejandra";
          };
        };
      in
      result.packages.${sys}.treefmt-config;
    expected = "flake.nix:alejandra";
  };

  # 6.4 self is available in top-level module functions
  testSelfAvailable = {
    expr =
      let
        fakeSelf = { outPath = "/my/flake"; rev = "abc123"; };
        result = lib.mkFlake { inputs = { inherit nixpkgs; self = fakeSelf; }; } {
          systems = [ sys ];
          imports = [
            # Top-level function using self → flake-scoped output
            ({ self, ... }: { flake.src = self.outPath; })
            # self captured in perSystem closure
            ({ self, ... }: {
              perSystem = { system, ... }: { packages.info = "${self.rev}-${system}"; };
            })
          ];
        };
      in
      { src = result.src; info = result.packages.${sys}.info; };
    expected = {
      src = "/my/flake";
      info = "abc123-${sys}";
    };
  };

  # 6.5 self' cross-module references via flake fixpoint
  testSelfPrimeCrossModule = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; self = result; }; } {
          systems = [ sys ];
          imports = [
            # Module A defines a package
            { perSystem = { pkgs, ... }: { packages.hello = "hello-pkg"; }; }
            # Module B reads module A's package via self'
            { perSystem = { self', ... }: { checks.test = "tested-${self'.packages.hello}"; }; }
          ];
        };
      in
      {
        pkg = result.packages.${sys}.hello;
        check = result.checks.${sys}.test;
      };
    expected = {
      pkg = "hello-pkg";
      check = "tested-hello-pkg";
    };
  };

  # lib is available from nixpkgs flake input without forcing pkgs eval
  testLibAvailable = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ sys ];
          perSystem = { lib, ... }: {
            packages.greeting = lib.concatStringsSep ", " [ "hello" "world" ];
          };
        };
      in
      result.packages.${sys}.greeting;
    expected = "hello, world";
  };

  # lib in top-level module function
  testLibInTopLevel = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } (
          { lib, ... }: {
            systems = [ sys ];
            flake.x = lib.optionalString true "yes";
          }
        );
      in
      result.x;
    expected = "yes";
  };

  # 6.6 withSystem in top-level module (nixosConfigurations pattern)
  testWithSystemFlake = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; self = result; }; } (
          { withSystem, ... }: {
            systems = [ sys ];
            perSystem = { pkgs, ... }: {
              packages.default = "my-default-pkg";
            };
            flake.nixosConfigurations.myhost = withSystem sys ({ pkgs, self', system, ... }: {
              system = system;
              defaultPkg = self'.packages.default;
            });
          }
        );
      in
      {
        system = result.nixosConfigurations.myhost.system;
        pkg = result.nixosConfigurations.myhost.defaultPkg;
        perSysPkg = result.packages.${sys}.default;
      };
    expected = {
      system = sys;
      pkg = "my-default-pkg";
      perSysPkg = "my-default-pkg";
    };
  };

  # 6.7 Nested adios submodule configuration via slash-path config keys
  testNestedSubmoduleConfig = {
    expr =
      let
        result = lib.mkFlake { inputs = { inherit nixpkgs; }; } {
          systems = [ sys ];
          imports = [
            {
              _type = "adiosModule";
              name = "treefmt";
              options.projectRootFile = { type = types.string; default = "default.nix"; };
              modules.nixfmt = {
                name = "nixfmt";
                options.enable = { type = types.bool; default = false; };
                impl = { options, ... }: {
                  formatters = if options.enable then [ "nixfmt" ] else [];
                };
              };
              impl = { options, ... }: {
                packages.root-file = options.projectRootFile;
              };
            }
          ];
          config = {
            treefmt = { projectRootFile = "flake.nix"; };
            "treefmt/nixfmt" = { enable = true; };
          };
        };
      in
      {
        rootFile = result.packages.${sys}.root-file;
        # Also verify the submodule got configured by calling it
        nixfmtEnabled =
          let
            tree = adiosLib {
              modules.treefmt = {
                options.projectRootFile = { type = types.string; default = "default.nix"; };
                modules.nixfmt = {
                  options.enable = { type = types.bool; default = false; };
                  impl = { options, ... }: { formatters = if options.enable then [ "nixfmt" ] else []; };
                };
                impl = { options, ... }: { root = options.projectRootFile; };
              };
            } {
              options = {
                "/treefmt" = { projectRootFile = "flake.nix"; };
                "/treefmt/nixfmt" = { enable = true; };
              };
            };
          in
          (tree.modules.treefmt.modules.nixfmt {}).formatters;
      };
    expected = {
      rootFile = "flake.nix";
      nixfmtEnabled = [ "nixfmt" ];
    };
  };
}
