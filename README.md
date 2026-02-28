
# adios-flake

> ⚠️ **Alpha** — API may change. Not yet recommended for production use.

_Composable flake outputs using the adios module system._

`adios-flake` provides an ergonomic `mkFlake` wrapper around the
[adios](https://github.com/adisbladis/adios) module system, enabling
composable flake outputs with memoized per-system evaluation.

## Features

- **Ergonomic API**: Write modules as simple functions (`{ pkgs, system, ... }: { packages.default = pkgs.hello; }`)
- **Memoized evaluation**: System-independent modules are evaluated once regardless of how many systems are configured
- **Three module styles**: Ergonomic functions, native adios modules, and static attrsets
- **Conflict detection**: Clear errors when two modules define the same output key
- **Cross-module references**: `self'` provides per-system access to other modules' outputs via the Nix flake fixpoint
- **`withSystem` helper**: Bridge per-system and system-agnostic outputs (e.g., nixosConfigurations)

## Getting Started

```console
nix flake init -t github:hercules-ci/adios-flake
```

## Quick Example

```nix
{
  inputs = {
    adios-flake.url = "github:hercules-ci/adios-flake";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs@{ adios-flake, self, ... }:
    adios-flake.lib.mkFlake {
      inherit inputs self;
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      perSystem = { pkgs, ... }: {
        packages.default = pkgs.hello;
      };
    };
}
```

## API Reference

### `mkFlake`

```nix
mkFlake {
  inputs;          # Required: flake inputs (must include nixpkgs)
  systems;         # Required: list of system strings
  self ? null;     # Optional: flake self-reference (enables self/self')
  perSystem ? null; # Optional: function { pkgs, system, inputs', self, self' } -> attrset
  modules ? [];    # Optional: list of modules (functions, native adios modules, or attrsets)
  config ? {};     # Optional: configure third-party module options by name
  flake ? {};      # Optional: system-agnostic outputs (attrset or function receiving { withSystem })
}
```

### Module Styles

#### Ergonomic Function (system-dependent)

Functions whose args include `pkgs`, `system`, `inputs'`, or `self'` are evaluated per-system:

```nix
({ pkgs, system, ... }: {
  packages.default = pkgs.hello;
  checks.test = pkgs.runCommand "test" {} "touch $out";
})
```

#### Ergonomic Function (system-independent)

Functions without system-specific args are memoized across all systems:

```nix
({ ... }: {
  packages.meta = "v1";
})
```

#### Native Adios Module

Full control over dependencies and typed options:

```nix
{
  name = "my-module";
  inputs.nixpkgs = { path = "/nixpkgs"; };
  options.greeting = { type = types.string; default = "hello"; };
  impl = { options, inputs, ... }: {
    packages.greet = options.greeting;
  };
}
```

#### Static Attrset

Simple constant contributions:

```nix
{ packages.meta = "v1"; }
```

### Third-Party Module Configuration

```nix
adios-flake.lib.mkFlake {
  inherit inputs self;
  systems = [ "x86_64-linux" ];
  modules = [ treefmt-nix.flakeModule ];
  config = {
    treefmt = { projectRootFile = "flake.nix"; };
    "treefmt/nixfmt" = { enable = true; };  # nested submodule
  };
};
```

### Cross-Module References with `self'`

```nix
adios-flake.lib.mkFlake {
  inherit inputs self;
  systems = [ "x86_64-linux" ];
  self = self;  # enable flake fixpoint
  modules = [
    ({ pkgs, ... }: { packages.hello = pkgs.hello; })
    ({ self', ... }: { checks.test = self'.packages.hello; })
  ];
};
```

### System-Agnostic Outputs with `withSystem`

```nix
adios-flake.lib.mkFlake {
  inherit inputs self;
  systems = [ "x86_64-linux" ];
  self = self;
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

## Architecture

adios-flake builds an adios module tree:

```
/ (root)
├── /nixpkgs        ← system + pkgs options, overridden per-system
├── /module-a       ← user modules (normalized to adios format)
├── /module-b
├── /_perSystem      ← from perSystem parameter
└── /_collector      ← merges all module results with conflict detection
```

Per-system evaluation uses adios's override chain: the first system triggers
a full tree evaluation, subsequent systems use `tree.override` which only
re-evaluates modules that depend on `/nixpkgs`. System-independent modules
retain their memoized results.

## Acknowledgements

adios-flake is a successor to [flake-parts](https://github.com/hercules-ci/flake-parts)
by [Hercules CI](https://hercules-ci.com/). The `mkFlake` API, `perSystem` pattern,
`self'`/`inputs'` helpers, `withSystem` bridge, and the overall vision of composable
flake modules all originate from flake-parts. This project reimplements those ideas
on top of the [adios](https://github.com/adisbladis/adios) module system for
memoized evaluation, but the design owes a great deal to the groundwork laid by
Robert Hensing and the flake-parts contributors.
