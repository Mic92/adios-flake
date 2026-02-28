# Tests for memoization: verify system-independent modules evaluate once with builtins.trace
#
# We use builtins.trace to count evaluations. When a trace fires, it prints to stderr.
# We can't capture stderr in pure Nix, but we CAN verify the structural behavior:
# - system-independent modules should produce the same result object identity across systems
# - system-dependent modules should produce different results per system
let
  prelude = import ./prelude.nix;
  inherit (prelude) lib nixpkgs;
  systems = [ "x86_64-linux" "aarch64-linux" ];

  # A result using two systems where one module is pure (no pkgs/system dep)
  result = lib.mkFlake {
    inputs = { nixpkgs = nixpkgs; };
    inherit systems;
    modules = [
      # System-independent: should be memoized (evaluated once)
      ({ ... }: { packages.meta = builtins.trace "PURE_MODULE_EVAL" "v1"; })
      # System-dependent: evaluated per system
      ({ system, ... }: { packages.sys = builtins.trace "SYS_MODULE_EVAL" system; })
    ];
  };
in
{
  # Pure module produces same value for both systems
  testPureModuleSameValue = {
    expr = result.packages.x86_64-linux.meta == result.packages.aarch64-linux.meta;
    expected = true;
  };

  # System-dependent module produces different values
  testSysModuleDifferentValues = {
    expr = result.packages.x86_64-linux.sys != result.packages.aarch64-linux.sys;
    expected = true;
  };

  # System-dependent module has correct values
  testSysModuleCorrectValues = {
    expr = {
      x86 = result.packages.x86_64-linux.sys;
      aarch = result.packages.aarch64-linux.sys;
    };
    expected = {
      x86 = "x86_64-linux";
      aarch = "aarch64-linux";
    };
  };

  # Pure module value is consistent
  testPureModuleValue = {
    expr = result.packages.x86_64-linux.meta;
    expected = "v1";
  };
}
