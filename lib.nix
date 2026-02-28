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
  adiosStructuralKeys = [ "options" "inputs" "impl" "modules" ];
  isNativeModule = m:
    isAttrs m && builtins.any (key: m ? ${key}) adiosStructuralKeys;

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
            normalized = normalizeFunction safeName (import mod) { inherit self flakeInputs; };
          in
          normalized // { _file = pathStr; }
        else if isFunction mod then
          normalizeFunction idx mod { inherit self flakeInputs; }
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
          [ (normalizeFunction "_perSystem" perSystem { inherit self flakeInputs; isPerSystem = true; }) ]
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

  # Normalize an ergonomic function module
  normalizeFunction = idx: fn: { self, flakeInputs, isPerSystem ? false }:
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
      inherit name;
      inputs = if sysDep then { nixpkgs = { path = "/nixpkgs"; }; } else {};
      impl =
        if sysDep then
          { inputs, ... }:
            let
              system = inputs.nixpkgs.system;
              pkgs = inputs.nixpkgs.pkgs;
              inputs' = mkInputsPrime flakeInputs system;
              self' = mkSelfPrime self system;
            in
            fn (builtins.intersectAttrs args {
              inherit lib pkgs system inputs' self self';
            })
        else
          { ... }:
            fn (builtins.intersectAttrs args ({
              inherit self;
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
  # Returns a lazy attrset keyed by standard flake per-system categories.
  #
  # We CANNOT enumerate self's keys (mapAttrs, attrNames, `?`) because self
  # is the flake fixpoint being constructed — any structural access triggers
  # infinite recursion.  Instead we pre-define per-system categories and
  # access self.${cat}.${system} directly.  Each value is a lazy thunk that
  # only forces when a module accesses that specific category.
  perSystemCategories = [
    "packages" "legacyPackages" "checks" "devShells" "apps" "formatter"
  ];

  mkSelfPrime = self: system:
    listToAttrs (map (cat: {
      name = cat;
      # Access self.${cat}.${system} lazily — this thunk is only forced
      # when a module reads self'.${cat}, at which point the fixpoint for
      # that particular category has resolved.
      value = self.${cat}.${system} or {};
    }) perSystemCategories);


  # Build the collector module that merges all user module results
  # Only include modules that have an impl (produce results)
  mkCollector = modules: resolveModuleName:
    let
      callableNames = map (m: m.name) (filter (m: m ? impl) modules);
    in
    {
      name = "_collector";
      inputs = listToAttrs (map (n: { name = n; value = { path = "/${n}"; }; }) callableNames);
      impl = { results, ... }:
        let
          # Pair each module result with its display name for error messages
          modPairs = map (modName: {
            name = resolveModuleName modName;
            value = results.${modName};
          }) (attrNames results);

          # Merge results by output category.
          # Category values are merged lazily — collision detection and the
          # actual merge happen inside a lazy `let` binding so that thunks
          # referencing `self` are not forced during collection.
          #
          # The accumulator tracks:
          #   merged.${cat} = lazy merged attrset of values
          #   owners.${cat}.${key} = name of module that first defined it
          # The accumulator stores { merged, owners } per category.
          # merged.${cat} = lazy attrset of merged values
          # owners.${cat} = lazy attrset mapping key -> module name
          # Both are only forced when the category is accessed in the
          # final output, at which point the fixpoint has resolved.
          mergeOne = acc: { name, value }:
            foldl' (acc': cat:
              if acc'.merged ? ${cat} then
                let
                  existing = acc'.merged.${cat};
                  entries = value.${cat};
                  prevOwners = acc'.owners.${cat};
                  # All lazy — attrNames/foldl' here only runs when
                  # someone accesses this category in the final output.
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
                  # Lazy: attrNames only forced when collision is checked
                  owners = acc'.owners // {
                    ${cat} = listToAttrs (map (k: {
                      name = k; value = name;
                    }) (attrNames value.${cat}));
                  };
                }
            ) acc (attrNames value);
        in
        foldl' mergeOne { merged = {}; owners = {}; } modPairs;
    };

  # Transpose { system -> { category.name } } to { category -> { system -> { name } } }
  # Scalar categories (non-plain-attrset values like formatter) are passed
  # through directly as category.${system} = value.
  transpose = perSystemResults:
    let
      systems = attrNames perSystemResults;
      # Collect all categories across all systems
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

      # Normalize all user modules
      normalizedModules = normalizeModules {
        inherit modules perSystem self;
        inherit flakeInputs;
      };

      moduleNames = map (m: m.name) normalizedModules;

      # Map safe module names back to file paths for error messages
      moduleFileMap = listToAttrs (
        filter (x: x.value != null)
          (map (m: { name = m.name; value = m._file or null; }) normalizedModules)
      );
      resolveModuleName = name: moduleFileMap.${name} or name;

      # Build the collector
      collector = mkCollector normalizedModules resolveModuleName;

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
          listToAttrs (map (m: { name = m.name; value = builtins.removeAttrs m [ "name" ]; }) normalizedModules)
          // { nixpkgs = builtins.removeAttrs nixpkgsModule [ "name" ]; }
          // { _collector = builtins.removeAttrs collector [ "name" ]; };
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
      allModulePaths = map (n: "/${n}") (moduleNames ++ [ "_collector" "nixpkgs" ]);
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

      # Collect results per system using evalModuleTree results (memoized)
      # rather than calling __functor which bypasses memoization.
      collectResults = tree:
        let collectorPath = "/_collector";
        in tree.modules._collector {};

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

      # Handle flake parameter (attrset or function)
      lib = flakeInputs.nixpkgs.lib or null;
      withSystem = system: fn:
        let
          pkgs = nixpkgsFor system;
          inputs' = mkInputsPrime flakeInputs system;
          self' = mkSelfPrime self system;
        in
        fn (builtins.intersectAttrs (functionArgs fn) {
          inherit lib pkgs system inputs' self';
        });

      flakeAttrs =
        if isFunction flake then
          flake { inherit withSystem; }
        else
          flake;

      # Deep-merge transposed per-system outputs with flake-level attrs.
      # Merge goes 2 levels deep (category → system) so that e.g.
      # `flake.checks.x86_64-linux.foo` merges with per-system
      # `checks.x86_64-linux.bar` instead of replacing it entirely.
      # Collisions at the leaf key level throw an error.
      mergeFlakeOutputs = transposed: flakeAttrs:
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
              else if isAttrs tVal && isAttrs fVal then
                # Both sides have this category — merge one level deeper (by system)
                let
                  allSystems = attrNames (tVal // fVal);
                in
                listToAttrs (map (sys:
                  let
                    tSys = tVal.${sys} or null;
                    fSys = fVal.${sys} or null;
                  in
                  {
                    name = sys;
                    value =
                      if tSys == null then fSys
                      else if fSys == null then tSys
                      else if isAttrs tSys && isAttrs fSys then
                        let
                          collisions = filter (k: tSys ? ${k}) (attrNames fSys);
                          # Look up which module defined each colliding key
                          sysOwners = perSystemOwners.${sys}.${cat} or {};
                          collisionMsgs = map (k:
                            "'${k}' defined by module '${sysOwners.${k} or "?"}' and by the 'flake' argument in flake.nix"
                          ) collisions;
                        in
                        if collisions != [] then
                          throw "mkFlake: conflict on ${cat}.${sys} — ${concatStringsSep "; " collisionMsgs}"
                        else
                          tSys // fSys
                      else
                        throw "mkFlake: cannot merge flake attr '${cat}.${sys}' — one side is not an attrset";
                  }
                ) allSystems)
              else
                throw "mkFlake: cannot merge flake attr '${cat}' — one side is not an attrset";
          }
        ) allCats);

    in
    mergeFlakeOutputs transposed flakeAttrs;

in
{
  inherit mkFlake;
}
