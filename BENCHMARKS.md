# adios-flake vs flake-parts: Evaluation Benchmarks

Measured on a real-world dotfiles flake with 36 inputs, 7 per-system modules,
clan-core integration, treefmt-nix, and home-manager.

## Setup

- **Machine**: Apple M3, 8 cores, 16 GiB RAM
- **Nix**: 2.34.0pre20260224_44e6d4c
- **flake-parts baseline**: [dotfiles@`7b3a760b0`](https://github.com/Mic92/dotfiles/commit/7b3a760b0) (main branch)
- **adios-flake**: [dotfiles@`1bbc6c6fb`](https://github.com/Mic92/dotfiles/commit/1bbc6c6fb) (adios-migration branch)
- **Method**: 5 runs per benchmark, `nix eval` with `NIX_SHOW_STATS=1`, eval cache cleared between runs. CPU time reported by the Nix evaluator (not wall clock).

The flake defines 3 systems (`aarch64-darwin`, `aarch64-linux`, `x86_64-linux`).

## Summary

| Benchmark | flake-parts | adios-flake | Speedup |
|:---|---:|---:|---:|
| `packages.aarch64-darwin` | 0.395s | 0.281s | **29% faster** |
| `formatter` (3 systems) | 0.512s | 0.360s | **30% faster** |
| `devShells` (3 systems) | 0.475s | 0.344s | **28% faster** |

## Detailed Results

### packages.aarch64-darwin (single system)

| Metric | flake-parts | adios-flake | Change |
|:---|---:|---:|---:|
| CPU time | 0.395s | 0.281s | **-29%** |
| Function calls | 231,607 | 171,412 | -26% |
| Prim op calls | 174,162 | 122,423 | -30% |
| Thunks created | 470,904 | 375,614 | -20% |
| Attr lookups | 138,076 | 88,272 | -36% |
| Attrset updates | 36,443 | 31,566 | -13% |
| Values copied (//) | 1,851,228 | 1,846,322 | -0.3% |
| GC heap | 66.8 MiB | 61.2 MiB | -8% |

### formatter (all 3 systems)

| Metric | flake-parts | adios-flake | Change |
|:---|---:|---:|---:|
| CPU time | 0.512s | 0.360s | **-30%** |
| Function calls | 606,028 | 434,096 | -28% |
| Prim op calls | 396,762 | 220,245 | -44% |
| Thunks created | 967,886 | 702,178 | -27% |
| Attr lookups | 368,713 | 229,494 | -38% |
| Attrset updates | 58,478 | 48,234 | -18% |
| Values copied (//) | 3,565,364 | 3,555,945 | -0.3% |
| GC heap | 156.5 MiB | 122.2 MiB | -22% |

### devShells (all 3 systems)

| Metric | flake-parts | adios-flake | Change |
|:---|---:|---:|---:|
| CPU time | 0.475s | 0.344s | **-28%** |
| Function calls | 532,094 | 376,656 | -29% |
| Prim op calls | 356,937 | 190,025 | -47% |
| Thunks created | 857,546 | 617,465 | -28% |
| Attr lookups | 327,912 | 198,150 | -40% |
| Attrset updates | 54,916 | 44,891 | -18% |
| Values copied (//) | 3,558,176 | 3,549,018 | -0.3% |
| GC heap | 130.9 MiB | 117.1 MiB | -11% |

## Analysis

The ~28–30% CPU time reduction comes from eliminating the NixOS module system
machinery that flake-parts uses to evaluate per-system outputs. adios-flake
replaces this with direct function dispatch and a memoized evaluation tree.

Notably, the `//` (attrset update) values-copied count is nearly identical
(~1.85M single-system, ~3.55M three-system). These copies are dominated by
nixpkgs import and upstream flake input processing, not the framework itself.
The framework's overhead is in the ~60K function calls and ~50K prim ops it
eliminates — the NixOS module system's `evalModules`, option type checking,
and merge machinery.
