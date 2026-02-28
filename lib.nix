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
        if isFunction mod then
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
              inherit pkgs system inputs' self self';
            })
        else
          { ... }:
            fn (builtins.intersectAttrs args {
              inherit self;
            });
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

  # Build self' from self for a given system
  mkSelfPrime = self: system:
    mapAttrs (_: v:
      if isAttrs v && v ? ${system} then v.${system}
      else {}
    ) (if self != null then self else {});

  # Build the collector module that merges all user module results
  # Only include modules that have an impl (produce results)
  mkCollector = modules:
    let
      callableNames = map (m: m.name) (filter (m: m ? impl) modules);
    in
    {
      name = "_collector";
      inputs = listToAttrs (map (n: { name = n; value = { path = "/${n}"; }; }) callableNames);
      impl = { results, ... }:
        let
          allResults = attrValues results;
          # Merge results by output category with conflict detection
          mergeOne = acc: modResult:
            foldl' (acc': cat:
              let
                existing = acc'.${cat} or {};
                entries = modResult.${cat};
                merged = foldl' (catAcc: key:
                  if catAcc ? ${key}
                  then throw "mkFlake: conflict on ${cat}.${key} — defined by multiple modules"
                  else catAcc // { ${key} = entries.${key}; }
                ) existing (attrNames entries);
              in
              acc' // { ${cat} = merged; }
            ) acc (attrNames modResult);
        in
        foldl' mergeOne {} allResults;
    };

  # Transpose { system -> { category.name } } to { category -> { system -> { name } } }
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

      # Build the collector
      collector = mkCollector normalizedModules;

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

      firstResults = collectResults firstTree;

      # Override for subsequent systems — only pass changed options (/nixpkgs)
      # so adios's diff propagation correctly memoizes unchanged modules
      subsequentResults = listToAttrs (map (sys:
        let
          overriddenTree = firstTree.override {
            options = {
              "/nixpkgs" = {
                system = sys;
                pkgs = nixpkgsFor sys;
              };
            };
          };
          results = collectResults overriddenTree;
        in
        { name = sys; value = results; }
      ) remainingSystems);

      # All per-system results
      perSystemResults = { ${firstSystem} = firstResults; } // subsequentResults;

      # Transpose to flake output shape
      transposed = transpose perSystemResults;

      # Handle flake parameter (attrset or function)
      withSystem = system: fn:
        let
          pkgs = nixpkgsFor system;
          inputs' = mkInputsPrime flakeInputs system;
          self' = mkSelfPrime self system;
        in
        fn (builtins.intersectAttrs (functionArgs fn) {
          inherit pkgs system inputs' self';
        });

      flakeAttrs =
        if isFunction flake then
          flake { inherit withSystem; }
        else
          flake;

    in
    # Merge transposed per-system outputs with flake attrs
    # flake attrs take precedence (as per spec D4 conflict resolution)
    transposed // flakeAttrs;

in
{
  inherit mkFlake;
}
