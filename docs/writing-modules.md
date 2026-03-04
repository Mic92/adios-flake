# Writing Reusable Modules

For simple cases, ergonomic functions and static attrsets are all you need.
When you're building a reusable module — something published as a flake
input for others to consume — native adios modules give you typed options,
explicit dependencies, and the ability to declare new output categories.

## Native Adios Modules

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

## Output Declarations

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

### Default categories

These categories are always available — you don't need to declare them:

- `packages`, `legacyPackages`, `checks`, `devShells`, `apps` → `"attrset"`
- `formatter` → `"scalar"`

Modules may redeclare a default category (e.g., to document intent) as long
as the type matches.

### Custom categories

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

### Conflict detection

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

## Example: treefmt-style Module

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

## Ergonomic Modules Don't Need Declarations

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
