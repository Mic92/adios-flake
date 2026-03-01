# End-to-end test: treefmt-style module declares `formatter` as scalar and
# `checks` as attrset, produces both outputs correctly
let
  prelude = import ./prelude.nix;
  inherit (prelude) lib types nixpkgs;
  systems = [ "x86_64-linux" "aarch64-linux" ];
in
{
  testTreefmtStyleModule = {
    expr =
      let
        # Simulate a treefmt-style third-party module
        treefmtModule = {
          name = "treefmt";
          outputs = {
            formatter = { type = "scalar"; };
            checks = { type = "attrset"; };
          };
          options.projectRootFile = { type = types.string; default = "flake.nix"; };
          inputs.nixpkgs = { path = "/nixpkgs"; };
          impl = { options, inputs, ... }: {
            formatter = "treefmt-wrapper-${inputs.nixpkgs.system}";
            checks.treefmt = "treefmt-check-${options.projectRootFile}-${inputs.nixpkgs.system}";
          };
        };

        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          inherit systems;
          modules = [
            treefmtModule
            # User module adds its own checks (non-overlapping)
            ({ system, ... }: {
              checks.my-test = "test-${system}";
            })
          ];
          config.treefmt = { projectRootFile = "project.toml"; };
        };
      in
      {
        formatter = result.formatter;
        checks = result.checks;
      };
    expected = {
      formatter = {
        x86_64-linux = "treefmt-wrapper-x86_64-linux";
        aarch64-linux = "treefmt-wrapper-aarch64-linux";
      };
      checks = {
        x86_64-linux = {
          treefmt = "treefmt-check-project.toml-x86_64-linux";
          my-test = "test-x86_64-linux";
        };
        aarch64-linux = {
          treefmt = "treefmt-check-project.toml-aarch64-linux";
          my-test = "test-aarch64-linux";
        };
      };
    };
  };
}
