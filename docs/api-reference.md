# API Reference

## `mkFlake`

```nix
mkFlake {
  inputs;          # Required: flake inputs (must include nixpkgs)
  systems;         # Required: list of system strings
  self ? null;     # Optional: pass `self` to enable self' in modules
  perSystem ? null; # Optional: function { pkgs, system, inputs', self, self' } -> attrset
  modules ? [];    # Optional: list of modules (functions, native adios modules, or attrsets)
  config ? {};     # Optional: configure third-party module options by name
  flake ? {};      # Optional: system-agnostic outputs (attrset or function receiving { withSystem })
}
```

## Module Styles

### Ergonomic Function (system-dependent)

Functions whose args include `pkgs`, `system`, `inputs'`, or `self'` are evaluated per-system:

```nix
({ pkgs, system, ... }: {
  packages.default = pkgs.hello;
  checks.test = pkgs.runCommand "test" {} "touch $out";
})
```

### Ergonomic Function (system-independent)

Functions without system-specific args are memoized across all systems:

```nix
({ ... }: {
  packages.meta = "v1";
})
```

### Static Attrset

Simple constant contributions:

```nix
{ packages.meta = "v1"; }
```

## Cross-Module References with `self'`

```nix
adios-flake.lib.mkFlake {
  inherit inputs self;
  systems = [ "x86_64-linux" ];
  modules = [
    ({ pkgs, ... }: { packages.hello = pkgs.hello; })
    ({ self', ... }: { checks.test = self'.packages.hello; })
  ];
};
```

## Multi-Module Flake

Modules can be passed as **paths** — the parent directory name is used in
error messages (e.g., `conflict on checks.foo — defined by module '.../pkgs/flake-module.nix'`):

```nix
adios-flake.lib.mkFlake {
  inherit inputs self;
  systems = [ "x86_64-linux" "aarch64-darwin" ];
  modules = [
    ./pkgs/flake-module.nix
    ./checks/flake-module.nix
    ./devshell/flake-module.nix
  ];
};
```

## System-Agnostic Outputs with `withSystem`

```nix
adios-flake.lib.mkFlake {
  inherit inputs self;
  systems = [ "x86_64-linux" ];
  perSystem = { pkgs, ... }: { packages.default = pkgs.hello; };
  flake = { withSystem }: {
    nixosConfigurations.myhost = withSystem "x86_64-linux" ({ pkgs, self', ... }:
      pkgs.lib.nixosSystem {
        modules = [{
          environment.systemPackages = [ self'.packages.default ];
        }];
      }
    );
  };
};
```
