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
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
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

  # 6.2 Multiple module styles: ergonomic function + native adios module + static attrset
  testMultipleModuleStyles = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
            # Ergonomic function
            ({ pkgs, ... }: { packages.from-fn = "fn-val"; })
            # Native adios module
            {
              name = "native";
              inputs.nixpkgs = { path = "/nixpkgs"; };
              impl = { inputs, ... }: { packages.from-native = inputs.nixpkgs.system; };
            }
            # Static attrset
            { packages.from-static = "static-val"; }
          ];
        };
      in
      result.packages.${sys};
    expected = {
      from-fn = "fn-val";
      from-native = sys;
      from-static = "static-val";
    };
  };

  # 6.3 Third-party module configuration via config parameter
  testThirdPartyConfig = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
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

  # 6.4 self is available in ergonomic functions
  testSelfAvailable = {
    expr =
      let
        fakeSelf = { outPath = "/my/flake"; rev = "abc123"; };
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          self = fakeSelf;
          modules = [
            # System-independent function using self
            ({ self, ... }: { packages.src = self.outPath; })
            # System-dependent function using self
            ({ self, system, ... }: { packages.info = "${self.rev}-${system}"; })
          ];
        };
      in
      result.packages.${sys};
    expected = {
      src = "/my/flake";
      info = "abc123-${sys}";
    };
  };

  # 6.5 self' cross-module references via flake fixpoint
  testSelfPrimeCrossModule = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          self = result;
          modules = [
            # Module A defines a package
            ({ pkgs, ... }: { packages.hello = "hello-pkg"; })
            # Module B reads module A's package via self'
            ({ self', ... }: { checks.test = "tested-${self'.packages.hello}"; })
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

  # 6.6 withSystem in flake function (nixosConfigurations pattern)
  testWithSystemFlake = {
    expr =
      let
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          self = result;
          perSystem = { pkgs, ... }: {
            packages.default = "my-default-pkg";
          };
          flake = { withSystem }: {
            nixosConfigurations.myhost = withSystem sys ({ pkgs, self', system, ... }: {
              system = system;
              defaultPkg = self'.packages.default;
            });
          };
        };
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
        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          systems = [ sys ];
          modules = [
            {
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
