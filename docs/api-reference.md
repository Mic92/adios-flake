# API Reference

## `mkFlake`

```nix
mkFlake { inherit inputs; } module
```

The first argument carries `inputs` (and optionally `specialArgs`). `self` is
read from `inputs.self` — the standard flake-parts convention.

`module` is a path, attrset, or function. When it's a function, it receives
`{ inputs, self, lib, withSystem, ... }`. In all cases it resolves to an
attrset with these (all optional) keys:

| Key | Meaning |
|---|---|
| `systems` | List of system strings. Must be set somewhere in the import tree. |
| `imports` | Further modules — walked recursively, depth-first. |
| `perSystem` | `{ pkgs, system, inputs', self', lib, ... }` → per-system outputs. |
| `flake` | System-agnostic outputs. Deep-merged across all imports. |
| `config` | adios option configuration by native module name. |

### Native adios modules

A native adios module placed in `imports` (recognised by `impl`, `outputs`,
or `_type = "adiosModule"`) passes straight through to the evaluation
engine — it isn't walked like a flake-parts module body. See
[Writing Reusable Modules](writing-modules.md).

### Compatibility note

This is signature-level compatibility with flake-parts — `imports` are
flattened and merged structurally. There is no `mkIf`, no priorities, no
submodule options. Simple flake-parts flakes work via
`inputs.foo.inputs.flake-parts.follows = "adios-flake"`; flakes that lean
on NixOS module system features (e.g. `flakeModules.partitions`) won't.

## Quick Example

```nix
{
  inputs = {
    adios-flake.url = "github:Mic92/adios-flake";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs@{ adios-flake, ... }:
    adios-flake.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      perSystem = { pkgs, ... }: {
        packages.default = pkgs.hello;
      };
      flake = {
        nixosModules.default = ./module.nix;
      };
    };
}
```

## `imports`

Each entry is a path, attrset, or function (same shape as the root module).
Paths are imported, functions are called with the top-level args, and the
resulting attrset's `imports` are recursed in turn.

```nix
adios-flake.lib.mkFlake { inherit inputs; } {
  systems = [ "x86_64-linux" "aarch64-darwin" ];
  imports = [
    ./pkgs/flake-module.nix
    ./checks/flake-module.nix
    ./devshell/flake-module.nix
  ];
};
```

```nix
# ./pkgs/flake-module.nix
{ ... }: {
  perSystem = { pkgs, ... }: {
    packages.hello = pkgs.hello;
  };
}
```

## `perSystem`

Called once per system. Its arguments tell the engine whether the closure is
system-dependent: a `perSystem` that asks for none of `pkgs`/`system`/
`inputs'`/`self'` is memoized — evaluated once regardless of how many systems
are configured.

```nix
perSystem = { pkgs, system, self', inputs', ... }: {
  packages.default = pkgs.hello;
  checks.test = self'.packages.default;
};
```

## `self'` — Cross-Module References

```nix
adios-flake.lib.mkFlake { inherit inputs; } {
  systems = [ "x86_64-linux" ];
  imports = [
    { perSystem = { pkgs, ... }: { packages.hello = pkgs.hello; }; }
    { perSystem = { self', ... }: { checks.test = self'.packages.hello; }; }
  ];
};
```

## `withSystem` — Bridging to System-Agnostic Outputs

`withSystem` is passed to top-level module functions. Use it to build
flake-scoped outputs (like `nixosConfigurations`) that need per-system
values.

```nix
adios-flake.lib.mkFlake { inherit inputs; } (
  { withSystem, ... }: {
    systems = [ "x86_64-linux" ];
    perSystem = { pkgs, ... }: { packages.default = pkgs.hello; };
    flake.nixosConfigurations.myhost = withSystem "x86_64-linux" ({ pkgs, self', ... }:
      pkgs.lib.nixosSystem {
        modules = [{
          environment.systemPackages = [ self'.packages.default ];
        }];
      }
    );
  }
);
```

`withSystem` is fed back into module arguments lazily through the engine's
fixpoint. Don't force it while computing `imports` or `systems` — that's a
genuine cycle.
