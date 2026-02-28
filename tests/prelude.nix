# Shared test prelude — resolves lib and types from the flake
let
  flake = builtins.getFlake "git+file://${toString ./..}";
  adios = flake.inputs.adios;
in
{
  lib = flake.lib;
  types = adios.adios.types;
  adiosLib = adios.adios;
  nixpkgs = <nixpkgs>;
  sys = builtins.currentSystem;
}
