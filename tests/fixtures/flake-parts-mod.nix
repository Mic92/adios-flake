{ ... }: {
  perSystem = { system, ... }: {
    packages.fromFile = "file-" + system;
  };
}
