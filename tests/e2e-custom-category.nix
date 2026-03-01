# End-to-end test: third-party module declares `containers` category,
# user module contributes to it, result has `containers.<system>.<name>`
let
  prelude = import ./prelude.nix;
  inherit (prelude) lib nixpkgs;
  systems = [ "x86_64-linux" "aarch64-linux" ];
in
{
  testCustomCategoryEndToEnd = {
    expr =
      let
        # Simulate a third-party module that declares containers
        containerFrameworkModule = {
          name = "container-framework";
          outputs = { containers = { type = "attrset"; }; };
          inputs.nixpkgs = { path = "/nixpkgs"; };
          impl = { inputs, ... }: {
            # Framework contributes a base container
            containers.base = "base-${inputs.nixpkgs.system}";
          };
        };

        result = lib.mkFlake {
          inputs = { nixpkgs = nixpkgs; };
          inherit systems;
          self = result;
          modules = [
            containerFrameworkModule
            # User module contributes to the declared category
            ({ system, ... }: {
              containers.web = "nginx-${system}";
            })
            # Another user module reads containers via self'
            ({ self', ... }: {
              checks.container-exists = "verified-${self'.containers.web}";
            })
          ];
        };
      in
      {
        containers = result.containers;
        check-x86 = result.checks.x86_64-linux.container-exists;
        check-aarch = result.checks.aarch64-linux.container-exists;
      };
    expected = {
      containers = {
        x86_64-linux = { base = "base-x86_64-linux"; web = "nginx-x86_64-linux"; };
        aarch64-linux = { base = "base-aarch64-linux"; web = "nginx-aarch64-linux"; };
      };
      check-x86 = "verified-nginx-x86_64-linux";
      check-aarch = "verified-nginx-aarch64-linux";
    };
  };
}
