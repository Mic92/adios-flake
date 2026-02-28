# Modules can be imported from separate files like this one.
# This is an ergonomic function module.

{ pkgs, ... }: {
  # Definitions like this are entirely equivalent to the ones
  # you may have directly in perSystem.
  packages.hello = pkgs.hello;
}
