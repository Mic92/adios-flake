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
nix flake init -t github:Mic92/adios-flake
```

## Quick Example

```nix
{
  inputs = {
    adios-flake.url = "github:Mic92/adios-flake";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs@{ adios-flake, ... }:
    adios-flake.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      perSystem = { pkgs, ... }: {
        packages.default = pkgs.hello;
      };
    };
}
```

## Documentation

- **[API Reference](docs/api-reference.md)** — `mkFlake` parameters, module styles, `self'`, `withSystem`
- **[Writing Reusable Modules](docs/writing-modules.md)** — native adios modules, output declarations, custom categories
- **[Benchmarks](BENCHMARKS.md)** — performance comparison with flake-parts

## Ecosystem

- **[red-tape](https://github.com/phaer/red-tape)** — Convention-based Nix project builder on top of adios-flake, inspired by [blueprint](https://github.com/numtide/blueprint). Drop your Nix files in the right places, and red-tape turns them into a complete flake — packages, devshells, checks, NixOS hosts, modules, templates, and lib — with zero boilerplate.

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
