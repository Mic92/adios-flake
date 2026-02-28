
# How do I contribute?

adios-flake is designed to be modular, so often you can write separate modules without changing the core.

Nonetheless, some changes can only be made here.

Step 1. Look for an open or closed issue. This may be the quickest path to a solution to your problem.

Step 2. If needed, open an issue. This way we can discuss the problem, and if necessary discuss changes.

Step 3. If needed, create a PR.


# Style

## Rule #1. Go with the flow

Write code that fits in. Don't reformat existing code. Write good docs and tests instead.

## Camel case

 - Functionality provided by adios-flake is in camelCase. Examples:
    - `mkFlake`
    - `withSystem`

## Operators and such

- The "contains attribute" operator is spelled without spaces:

  ```nix
  if x?a then x.a else "does not have a"
  ```

- `@` pattern goes before and uses no extra spaces:

  ```nix
  pair@{ name, value }:
  ```
