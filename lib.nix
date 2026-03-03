{
  # The adios flake input
  adios,
}:
let
  # When adios is a flake input, it has an `adios` attribute (the module system).
  # When it's a local path (for testing), we import it directly.
  adiosLib =
    if builtins.isAttrs adios && adios ? adios
    then adios.adios
    else import (adios + "/adios");

  inherit (builtins)
    attrNames
    attrValues
    concatMap
    concatStringsSep
    elem
    filter
    foldl'
    functionArgs
    isAttrs
    isFunction
    isList
    length
    listToAttrs
    mapAttrs
    head
    tail
    ;

  # Check if an attrset is a native adios module (has structural keys)
  adiosStructuralKeys = [ "options" "inputs" "impl" "modules" "outputs" ];
  isNativeModule = m:
    isAttrs m && builtins.any (key: m ? ${key}) adiosStructuralKeys;

  # Default output category declarations.
  # These are always present even when no module declares outputs.
  defaultOutputDeclarations = {
    packages      = { type = "attrset"; };
    legacyPackages = { type = "attrset"; };
    checks        = { type = "attrset"; };
    devShells     = { type = "attrset"; };
    apps          = { type = "attrset"; };
    formatter     = { type = "scalar"; };
  };

  defaultFlakeOutputs = [
    "nixosConfigurations"
    "darwinConfigurations"
    "nixosModules"
    "darwinModules"
    "homeModules"
    "overlays"
    "templates"
    "lib"
  ];

  # Scan normalized modules for `outputs` declarations and merge with defaults.
  # Throws on conflicting merge types for the same category.
  # Returns { declarations, flakeOutputs } where
  # flakeOutputs is the list of category names that are
  # flake-scoped (defaults + module-declared via scope = "flake").
  collectOutputDeclarations = modules:
    let
      # Collect all (moduleName, category, type) triples from module outputs
      modulesWithOutputs = filter (m: m ? outputs) modules;

      # Fold over modules, merging their declarations
      collected = foldl' (acc: mod:
        foldl' (acc': cat:
          let
            decl = mod.outputs.${cat};
            newType = decl.type;
            newScope = decl.scope or null;
            modName = mod.name or "?";
          in
          if acc'.declarations ? ${cat} then
            if acc'.declarations.${cat}.type != newType then
              throw "mkFlake: output category '${cat}' declared as '${acc'.declarations.${cat}.type}' by module '${acc'.declaredBy.${cat}}' and '${newType}' by module '${modName}'"
            else
              # Consistent redeclaration — keep existing
              acc'
          else
            {
              declarations = acc'.declarations // { ${cat} = { type = newType; }; };
              declaredBy = acc'.declaredBy // { ${cat} = modName; };
              flakeDeclarations = acc'.flakeDeclarations
                ++ (if newScope == "flake" then [ cat ] else []);
            }
        ) acc (attrNames mod.outputs)
      ) { declarations = {}; declaredBy = {}; flakeDeclarations = []; } modulesWithOutputs;

      # Merge with defaults: module declarations override defaults,
      # but check for conflicts with defaults too
      mergedWithDefaults = foldl' (acc: cat:
        let
          defaultType = defaultOutputDeclarations.${cat}.type;
        in
        if acc ? ${cat} then
          if acc.${cat}.type != defaultType then
            throw "mkFlake: output category '${cat}' declared as '${acc.${cat}.type}' by module '${collected.declaredBy.${cat}}' but default type is '${defaultType}'"
          else
            acc
        else
          acc // { ${cat} = { type = defaultType; }; }
      ) collected.declarations (attrNames defaultOutputDeclarations);
    in
    {
      declarations = mergedWithDefaults;
      flakeOutputs = defaultFlakeOutputs ++ collected.flakeDeclarations;
    };

  # System-dependent argument names
  systemDepArgs = [ "pkgs" "system" "inputs'" "self'" ];

  # Check if a function needs per-system evaluation
  isSystemDependent = fn:
    let args = functionArgs fn;
    in builtins.any (arg: args ? ${arg}) systemDepArgs;

  # Auto-naming counters
  normalizeModules =
    { modules
    , perSystem ? null
    , self ? null
    , flakeInputs ? {}
    , getSelfPrime
    , withSystem
    }:
    let
      # Normalize a single module with index for auto-naming
      normalizeOne = idx: mod:
        if builtins.isPath mod then
          # Path: import it and use the file path for error messages.
          # Replace '/' with '-' for the adios tree key (which uses '/'
          # as a path separator) but keep the original path as `_file`.
          let
            pathStr = toString mod;
            safeName = builtins.replaceStrings [ "/" ] [ "-" ] pathStr;
            normalized = normalizeFunction safeName (import mod) { inherit self flakeInputs getSelfPrime withSystem; };
          in
          normalized // { _file = pathStr; }
        else if isFunction mod then
          normalizeFunction idx mod { inherit self flakeInputs getSelfPrime withSystem; }
        else if isNativeModule mod then
          # Native adios module - use as-is, ensure it has a name
          mod // { name = mod.name or "_native_${toString idx}"; }
        else if isAttrs mod then
          normalizeStatic idx mod
        else
          throw "mkFlake: module at index ${toString idx} is not a function, attrset, or native adios module";

      normalizedModules = builtins.genList (idx: normalizeOne idx (builtins.elemAt modules idx)) (length modules);

      # Add perSystem if provided
      perSystemModule =
        if perSystem != null then
          [ (normalizeFunction "_perSystem" perSystem { inherit self flakeInputs getSelfPrime withSystem; isPerSystem = true; }) ]
        else
          [];

      allModules = normalizedModules ++ perSystemModule;

      # Check for duplicate names
      names = map (m: m.name) allModules;
      findDuplicates = ns:
        let
          check = foldl' (acc: n:
            if elem n acc.seen
            then acc // { dups = acc.dups ++ [ n ]; }
            else acc // { seen = acc.seen ++ [ n ]; }
          ) { seen = []; dups = []; } ns;
        in check.dups;
      dups = findDuplicates names;
    in
    if dups != []
    then throw "mkFlake: duplicate module name(s): ${builtins.concatStringsSep ", " dups}"
    else allModules;

  # Normalize an ergonomic function module.
  # getSelfPrime: system → self' attrset (provided lazily by mkFlake)
  normalizeFunction = idx: fn: { self, flakeInputs, getSelfPrime, withSystem, isPerSystem ? false }:
    let
      args = functionArgs fn;
      sysDep = isSystemDependent fn;
      name = if isPerSystem then "_perSystem"
             else if builtins.isInt idx then "_fn_${toString idx}"
             else toString idx;
      # Extract lib from the nixpkgs flake input (cheap — no package eval).
      # The nixpkgs flake always exposes a top-level `lib`.  When nixpkgs
      # is a plain path (e.g. <nixpkgs> in tests), fall back to importing
      # just the lib/ subdirectory — no package evaluation needed.
      lib =
        if flakeInputs ? nixpkgs then
          flakeInputs.nixpkgs.lib or (import (flakeInputs.nixpkgs + "/lib"))
        else
          null;
    in
    {
      inherit name sysDep;
      inputs = if sysDep then { nixpkgs = { path = "/nixpkgs"; }; } else {};
      impl =
        if sysDep then
          { inputs, ... }:
            let
              system = inputs.nixpkgs.system;
              pkgs = inputs.nixpkgs.pkgs;
              inputs' = mkInputsPrime flakeInputs system;
              self' = getSelfPrime system;
            in
            fn (builtins.intersectAttrs args {
              inherit lib pkgs system inputs' self self' withSystem;
            })
        else
          { ... }:
            fn (builtins.intersectAttrs args ({
              inherit self withSystem;
            } // (if lib != null then { inherit lib; } else {})));
    };

  # Normalize a static attrset module
  normalizeStatic = idx: attrs:
    {
      name = "_static_${toString idx}";
      impl = { ... }: attrs;
    };

  # Build inputs' from flake inputs for a given system
  mkInputsPrime = flakeInputs: system:
    mapAttrs (_: input:
      if isAttrs input then
        (input.packages.${system} or {})
        // (input.legacyPackages.${system} or {})
        // (builtins.removeAttrs input [ "packages" "legacyPackages" ])
      else input
    ) flakeInputs;

  # Build self' from self for a given system.
  # Returns a lazy attrset keyed by per-system categories derived from
  # output declarations.
  #
  # We CANNOT enumerate self's keys (mapAttrs, attrNames, `?`) because self
  # is the flake fixpoint being constructed — any structural access triggers
  # infinite recursion.  Instead we use the pre-collected category names and
  # access self.${cat}.${system} directly.  Each value is a lazy thunk that
  # only forces when a module accesses that specific category.
  mkSelfPrime = categories: self: system:
    listToAttrs (map (cat: {
      name = cat;
      # Access self.${cat}.${system} lazily — this thunk is only forced
      # when a module reads self'.${cat}, at which point the fixpoint for
      # that particular category has resolved.
      value = self.${cat}.${system} or {};
    }) categories);

  # Merge two attrsets, throwing on key collisions.
  # mkMsg: key → error message string
  mergeDisjoint = mkMsg: a: b:
    let
      collisions = filter (k: a ? ${k}) (attrNames b);
    in
    if collisions != []
    then throw (mkMsg (head collisions))
    else a // b;

  # Build a collector adios module that merges results from all user modules.
  #
  # acceptCat  — which categories to collect
  # guardMod   — optional per-module gate (name → string|null; string = error)
  # outputDeclarations — category→{type} map (null to skip scalar handling)
  #
  # Returns { merged, owners }.
  mkResultCollector =
    { name
    , acceptCat
    , guardMod ? _: null
    , outputDeclarations ? null
    , modules
    , resolveModuleName
    }:
    let
      callableNames = map (m: m.name) (filter (m: m ? impl) modules);

      mergeTypeOf = cat:
        if outputDeclarations != null
        then (outputDeclarations.${cat} or { type = "attrset"; }).type
        else "attrset";

      mergeAttrsetCat = acc': cat: name: value:
        if acc'.merged ? ${cat} then
          let
            existing = acc'.merged.${cat};
            entries = value.${cat};
            prevOwners = acc'.owners.${cat};
            merged = foldl' (catAcc: key:
              if catAcc ? ${key}
              then throw "mkFlake: conflict on ${cat}.${key} — defined by module '${prevOwners.${key} or "?"}' and '${name}'"
              else catAcc // { ${key} = entries.${key}; }
            ) existing (attrNames entries);
            owners = prevOwners
              // listToAttrs (map (k: { name = k; value = name; }) (attrNames entries));
          in
          {
            merged = acc'.merged // { ${cat} = merged; };
            owners = acc'.owners // { ${cat} = owners; };
          }
        else
          {
            merged = acc'.merged // { ${cat} = value.${cat}; };
            owners = acc'.owners // {
              ${cat} = listToAttrs (map (k: {
                name = k; value = name;
              }) (attrNames value.${cat}));
            };
          };
    in
    {
      inherit name;
      inputs = listToAttrs (map (n: { name = n; value = { path = "/${n}"; }; }) callableNames);
      impl = { results, ... }:
        let
          modPairs = map (modName: {
            name = resolveModuleName modName;
            value = results.${modName};
          }) (attrNames results);

          mergeOne = acc: { name, value }:
            foldl' (acc': cat:
              if ! acceptCat cat then acc'
              else
              let guard = guardMod name; in
              if guard != null then throw guard
              else
              let catType = mergeTypeOf cat; in
              if catType == "scalar" then
                if acc'.merged ? ${cat} then
                  throw "mkFlake: scalar output '${cat}' defined by module '${acc'.owners.${cat}}' and '${name}'"
                else
                  {
                    merged = acc'.merged // { ${cat} = value.${cat}; };
                    owners = acc'.owners // { ${cat} = name; };
                  }
              else
                mergeAttrsetCat acc' cat name value
            ) acc (attrNames value);
        in
        foldl' mergeOne { merged = {}; owners = {}; } modPairs;
    };

  # Transpose { system -> { category.name } } to { category -> { system -> { name } } }
  transpose = perSystemResults:
    let
      systems = attrNames perSystemResults;
      allCategories = builtins.foldl' (acc: sys:
        acc ++ (filter (c: ! elem c acc) (attrNames perSystemResults.${sys}))
      ) [] systems;
    in
    listToAttrs (map (cat: {
      name = cat;
      value = listToAttrs (map (sys: {
        name = sys;
        value = perSystemResults.${sys}.${cat} or {};
      }) systems);
    }) allCategories);

  # The main mkFlake function
  mkFlake =
    { inputs
    , systems
    , modules ? []
    , perSystem ? null
    , config ? {}
    , flake ? {}
    , self ? null
    }:
    assert inputs ? nixpkgs || throw "mkFlake: `inputs` must contain a `nixpkgs` input";
    assert isList systems || throw "mkFlake: `systems` must be a list of system strings";
    let
      flakeInputs = builtins.removeAttrs inputs [ "self" ];

      # Collect output declarations from modules + defaults.
      # This is computed lazily — it only inspects the `outputs` field of
      # native modules (structural access), not `impl`, so it's safe to
      # reference normalizedModules here even though normalizedModules
      # captures getSelfPrime which captures outputDeclarations.
      collected = collectOutputDeclarations normalizedModules;
      outputDeclarations = collected.declarations;
      flakeOutputs = collected.flakeOutputs;

      # Category names derived from output declarations (for self')
      categoryNames = attrNames outputDeclarations;

      # getSelfPrime: system → self' — captures categories lazily
      getSelfPrime = mkSelfPrime categoryNames self;

      withSystem = system: fn:
        let
          pkgs = nixpkgsFor system;
          inputs' = mkInputsPrime flakeInputs system;
          self' = getSelfPrime system;
        in
        fn (builtins.intersectAttrs (functionArgs fn) {
          lib = flakeInputs.nixpkgs.lib;
          inherit pkgs system inputs' self';
        });

      # Normalize all user modules
      normalizedModules = normalizeModules {
        inherit modules perSystem self getSelfPrime withSystem;
        inherit flakeInputs;
      };

      moduleNames = map (m: m.name) normalizedModules;

      # Map safe module names back to file paths for error messages
      moduleFileMap = listToAttrs (
        filter (x: x.value != null)
          (map (m: { name = m.name; value = m._file or null; }) normalizedModules)
      );
      resolveModuleName = name: moduleFileMap.${name} or name;

      # Resolved names of system-dependent modules
      sysDepNames = map (m: resolveModuleName m.name)
        (filter (m: m.sysDep or false) normalizedModules);

      # Per-system collector (excludes flake-scoped keys)
      collector = mkResultCollector {
        name = "_collector";
        acceptCat = cat: ! elem cat flakeOutputs;
        inherit outputDeclarations resolveModuleName;
        modules = normalizedModules;
      };

      # Flake collector (only flake-scoped keys, rejects system-dependent modules)
      flakeCollector = mkResultCollector {
        name = "_flake";
        acceptCat = cat: elem cat flakeOutputs;
        guardMod = modName:
          if elem modName sysDepNames
          then "mkFlake: module '${modName}' produces flake-scoped output but depends on system-specific arguments (pkgs, system, inputs', self'). Split it into a per-system module and a system-independent module that uses `withSystem`."
          else null;
        modules = normalizedModules;
        inherit resolveModuleName;
      };

      # Build the /nixpkgs internal module
      nixpkgsModule = {
        name = "nixpkgs";
        options = {
          system = {
            type = adiosLib.types.string;
          };
          pkgs = {
            type = adiosLib.types.attrs;
          };
        };
      };

      # Root module tree definition
      rootDef = {
        modules =
          listToAttrs (map (m: { name = m.name; value = builtins.removeAttrs m [ "name" "outputs" "_file" ]; }) normalizedModules)
          // { nixpkgs = builtins.removeAttrs nixpkgsModule [ "name" ]; }
          // { _collector = builtins.removeAttrs collector [ "name" ]; }
          // { _flake = builtins.removeAttrs flakeCollector [ "name" ]; };
      };

      # Convert config parameter to adios option paths
      configOptions = listToAttrs (concatMap (key:
        let
          path = "/${builtins.replaceStrings [ "/" ] [ "/" ] key}";
        in
        [ { name = path; value = config.${key}; } ]
      ) (attrNames config));

      # Include all modules in the resolution by providing (possibly empty)
      # options for each. This ensures adios resolves the full dependency graph
      # and enables memoization via evalModuleTree.results.
      allModulePaths = map (n: "/${n}") (moduleNames ++ [ "_collector" "_flake" "nixpkgs" ]);
      emptyModuleOptions = listToAttrs (map (p: { name = p; value = {}; }) allModulePaths);

      # Evaluate for the first system
      firstSystem = head systems;
      remainingSystems = tail systems;

      nixpkgsFor = system: import inputs.nixpkgs { inherit system; };

      mkOptions = system: emptyModuleOptions // configOptions // {
        "/nixpkgs" = {
          system = system;
          pkgs = nixpkgsFor system;
        };
      };

      # First full evaluation
      firstTree = adiosLib rootDef { options = mkOptions firstSystem; };

      # Collect per-system results
      collectResults = tree: tree.modules._collector {};

      # Collector returns { merged, owners } per system
      firstCollected = collectResults firstTree;

      # Override for subsequent systems — only pass changed options (/nixpkgs)
      # so adios's diff propagation correctly memoizes unchanged modules
      subsequentCollected = listToAttrs (map (sys:
        let
          overriddenTree = firstTree.override {
            options = {
              "/nixpkgs" = {
                system = sys;
                pkgs = nixpkgsFor sys;
              };
            };
          };
        in
        { name = sys; value = collectResults overriddenTree; }
      ) remainingSystems);

      allCollected = { ${firstSystem} = firstCollected; } // subsequentCollected;

      # Split merged results for transposition
      perSystemResults = mapAttrs (_: c: c.merged) allCollected;

      # Per-system ownership maps for error messages
      perSystemOwners = mapAttrs (_: c: c.owners) allCollected;

      # Transpose to flake output shape
      transposed = transpose perSystemResults;

      # Collect flake-scoped outputs (evaluated once — system-independent)
      flakeCollected = firstTree.modules._flake {};
      moduleFlakeAttrs = flakeCollected.merged;
      flakeOwners = flakeCollected.owners;

      # Resolve the user-provided `flake` parameter
      userFlakeAttrs =
        if isFunction flake then
          flake { inherit withSystem; }
        else
          flake;

      # Merge module flake outputs with user flake parameter
      allFlakeAttrs = foldl' (acc: cat:
        let
          mVal = moduleFlakeAttrs.${cat} or null;
          uVal = userFlakeAttrs.${cat} or null;
          catOwners = flakeOwners.${cat} or {};
          val =
            if mVal == null then uVal
            else if uVal == null then mVal
            else mergeDisjoint
              (k: "mkFlake: conflict on flake output '${cat}' — '${k}' defined by module '${catOwners.${k} or "?"}' and by the 'flake' argument")
              mVal uVal;
        in
        acc // { ${cat} = val; }
      ) {} (attrNames (moduleFlakeAttrs // userFlakeAttrs));

      # Deep-merge transposed per-system outputs with flake-level attrs.
      # Merge goes 2 levels deep (category → system) so that e.g.
      # `flake.checks.x86_64-linux.foo` merges with per-system
      # `checks.x86_64-linux.bar` instead of replacing it entirely.
      mergeOutputs = transposed: flakeAttrs:
        let
          allCats = attrNames (transposed // flakeAttrs);
        in
        listToAttrs (map (cat:
          let
            tVal = transposed.${cat} or null;
            fVal = flakeAttrs.${cat} or null;
          in
          {
            name = cat;
            value =
              if tVal == null then fVal
              else if fVal == null then tVal
              else
                # Both sides have this category — merge one level deeper (by system)
                let
                  allSystems = attrNames (tVal // fVal);
                in
                listToAttrs (map (sys:
                  let
                    tSys = tVal.${sys} or null;
                    fSys = fVal.${sys} or null;
                    sysOwners = perSystemOwners.${sys}.${cat} or {};
                  in
                  {
                    name = sys;
                    value =
                      if tSys == null then fSys
                      else if fSys == null then tSys
                      else mergeDisjoint
                        (k: "mkFlake: conflict on ${cat}.${sys} — '${k}' defined by module '${sysOwners.${k} or "?"}' and by the 'flake' argument")
                        tSys fSys;
                  }
                ) allSystems);
          }
        ) allCats);

    in
    mergeOutputs transposed allFlakeAttrs;

in
{
  inherit mkFlake;
}
