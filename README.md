
# adios-flake

> ⚠️ **Alpha** — API may change. Not yet recommended for production use.

_Composable flake outputs using the adios module system — the ergonomics of
flake-parts without the evaluation overhead._

## Why?

This project was born from a conversation between
[@adisbladis](https://github.com/adisbladis) and
[@MatthewCroughan](https://github.com/MatthewCroughan). Matthew loved the
ergonomics of flake-parts — the composable modules, `perSystem`, `self'` — but
adisbladis had been digging into the evaluation performance and pointed out
how much overhead the NixOS module system adds to every flake evaluation,
especially when you multiply it across a graph of flake inputs that all use
flake-parts.

The result: **adios-flake**. It reimplements the flake-parts API on top of
[adios](https://github.com/adisbladis/adios), a module system designed for
memoized evaluation. You get the same `mkFlake` you know and love, but
evaluations run **~30% faster** with ~40% fewer attribute lookups and nearly
half the primitive operations. See [BENCHMARKS.md](BENCHMARKS.md) for the
numbers.

## Features

- **Familiar API**: Drop-in `mkFlake` with `perSystem`, `self'`, `inputs'`, and `withSystem` — if you've used flake-parts, you already know how this works
- **Memoized evaluation**: System-independent modules are evaluated once regardless of how many systems are configured
- **Three module styles**: Ergonomic functions, native adios modules, and static attrsets
- **Extensible output categories**: Modules can declare new flake output categories (e.g., `containers`, `templates`) with merge semantics (`attrset` or `scalar`)
- **Conflict detection**: Clear errors when two modules define the same output key, or when a scalar output has multiple providers
- **Cross-module references**: `self'` automatically includes module-declared categories, providing per-system access to other modules' outputs via the Nix flake fixpoint
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
  self ? null;     # Optional: pass `self` to enable self' in modules
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

#### Static Attrset

Simple constant contributions:

```nix
{ packages.meta = "v1"; }
```

### Cross-Module References with `self'`

```nix
adios-flake.lib.mkFlake {
  inherit inputs self;
  systems = [ "x86_64-linux" ];
  self = self;
  modules = [
    ({ pkgs, ... }: { packages.hello = pkgs.hello; })
    ({ self', ... }: { checks.test = self'.packages.hello; })
  ];
};
```

### Multi-Module Flake

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

## Writing Reusable Modules

For simple cases, ergonomic functions and static attrsets are all you need.
When you're building a reusable module — something published as a flake
input for others to consume — native adios modules give you typed options,
explicit dependencies, and the ability to declare new output categories.

### Native Adios Modules

Native modules have a `name`, an `impl` function, and optionally `options`
for typed configuration. `inputs.nixpkgs = { path = "/nixpkgs"; }` declares
a dependency on the internal nixpkgs node — this is how native modules access
`system` and `pkgs`:

```nix
{
  name = "treefmt";
  options.projectRootFile = { type = types.string; default = "flake.nix"; };
  inputs.nixpkgs = { path = "/nixpkgs"; };
  impl = { options, inputs, ... }: {
    packages.treefmt-config = options.projectRootFile;
  };
}
```

Consumers configure them via the `config` parameter:

```nix
adios-flake.lib.mkFlake {
  inherit inputs self;
  systems = [ "x86_64-linux" ];
  modules = [ treefmt-nix.flakeModule ];
  config.treefmt = { projectRootFile = "project.toml"; };
};
```

### Output Declarations

Native adios modules can include an `outputs` attrset that tells `mkFlake`
what flake output categories the module produces and how they merge:

```nix
{
  name = "my-containers";
  outputs = {
    containers = { type = "attrset"; };  # merged by key, collision = error
  };
  inputs.nixpkgs = { path = "/nixpkgs"; };
  impl = { inputs, ... }: {
    containers.nginx = "nginx-container-${inputs.nixpkgs.system}";
  };
}
```

There are two merge types:

| Type | Behavior | Example categories |
|------|----------|--------------------|
| `"attrset"` | Merge contributions by key; error on duplicate keys | `packages`, `checks`, `devShells`, `apps` |
| `"scalar"` | Exactly one module may provide a value per system; error if two modules contribute | `formatter` |

#### Default categories

These categories are always available — you don't need to declare them:

- `packages`, `legacyPackages`, `checks`, `devShells`, `apps` → `"attrset"`
- `formatter` → `"scalar"`

Modules may redeclare a default category (e.g., to document intent) as long
as the type matches.

#### Custom categories

Any module can introduce new categories. Once declared, the category is
available in `self'` and appears in the final flake output:

```nix
# Third-party module (e.g., in a separate flake)
{
  name = "container-framework";
  outputs = {
    containers = { type = "attrset"; };
  };
  inputs.nixpkgs = { path = "/nixpkgs"; };
  impl = { inputs, ... }: {
    containers.base = mkBaseContainer inputs.nixpkgs.pkgs;
  };
}
```

Users and other modules can then contribute to the new category:

```nix
# User's flake
adios-flake.lib.mkFlake {
  inherit inputs self;
  systems = [ "x86_64-linux" ];
  self = self;
  modules = [
    container-framework.flakeModule
    # Contribute to the declared category
    ({ system, ... }: {
      containers.web = mkWebContainer system;
    })
    # Read it via self'
    ({ self', ... }: {
      checks.container-test = testContainer self'.containers.web;
    })
  ];
};
```

Result: `containers.x86_64-linux.base`, `containers.x86_64-linux.web`,
and `checks.x86_64-linux.container-test` all appear in the flake output.

#### Conflict detection

If two modules declare the same category with different types, `mkFlake`
throws at tree-construction time — before any evaluation:

```
mkFlake: output category 'foo' declared as 'attrset' by module 'mod-a'
  and 'scalar' by module 'mod-b'
```

If two modules both provide a scalar output (like `formatter`), `mkFlake`
throws at evaluation time:

```
mkFlake: scalar output 'formatter' defined by module 'treefmt' and 'my-fmt'
```

### Example: treefmt-style Module

A complete reusable module that declares `formatter` as scalar and `checks`
as attrset, with configurable options:

```nix
# treefmt-nix/flake-module.nix
{
  name = "treefmt";
  outputs = {
    formatter = { type = "scalar"; };
    checks    = { type = "attrset"; };
  };
  options.projectRootFile = { type = types.string; default = "flake.nix"; };
  inputs.nixpkgs = { path = "/nixpkgs"; };
  impl = { options, inputs, ... }:
    let
      pkgs = inputs.nixpkgs.pkgs;
      wrapped = pkgs.writeShellScriptBin "treefmt" ''
        exec ${pkgs.treefmt}/bin/treefmt --config-file ${options.projectRootFile} "$@"
      '';
    in {
      formatter = wrapped;
      checks.treefmt = pkgs.runCommand "treefmt-check" {} ''
        ${wrapped}/bin/treefmt --fail-on-change
        touch $out
      '';
    };
}
```

Usage:

```nix
adios-flake.lib.mkFlake {
  inherit inputs self;
  systems = [ "x86_64-linux" ];
  modules = [ treefmt-nix.flakeModule ];
  config.treefmt = { projectRootFile = "project.toml"; };
};
```

### Ergonomic Modules Don't Need Declarations

Simple function modules and static attrsets never need `outputs`. Their
return keys are automatically treated as `"attrset"` categories:

```nix
# This just works — no outputs declaration needed
({ pkgs, ... }: {
  packages.hello = pkgs.hello;
  checks.test = pkgs.runCommand "test" {} "touch $out";
})
```

Output declarations are only needed when a module:
- Introduces a **new** output category (not in the default set)
- Needs **scalar** merge semantics (one provider per system)
- Wants to **document** what categories it produces (good practice for
  published modules)

## Acknowledgements

adios-flake stands on the shoulders of
[flake-parts](https://github.com/hercules-ci/flake-parts) by
[Hercules CI](https://hercules-ci.com/). The `mkFlake` API, `perSystem`
pattern, `self'`/`inputs'` helpers, `withSystem` bridge, and the overall
vision of composable flake modules all originate from flake-parts. The design
owes a great deal to the groundwork laid by Robert Hensing and the flake-parts
contributors — we just wanted it faster.

Thanks to [@adisbladis](https://github.com/adisbladis) for creating the
[adios](https://github.com/adisbladis/adios) module system that makes the
memoized evaluation possible, and to
[@MatthewCroughan](https://github.com/MatthewCroughan) for insisting that
we shouldn't have to choose between ergonomics and performance.
