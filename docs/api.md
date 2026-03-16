# API Reference

## nixy.eval

```nix
nixy.eval {
  lib;
  imports ? [ ];
  args ? { };
  exclude ? null;
  disabledModules ? [ ];
}
```

| Parameter | Description |
|-----------|-------------|
| `lib` | Nixpkgs `lib` |
| `imports` | Directories, `.nix` files, functions, attrsets, or lists thereof |
| `args` | Extra arguments available in nixy-level modules via `specialArgs` |
| `exclude` | `{ name, path } -> bool` — return `true` to skip a file during scanning |
| `disabledModules` | List of module paths or `{ key }` attrsets to exclude from evaluation |

**Returns:**

```nix
{
  nodes.<n> = {
    schema = { ... };
    traits = [ ... ];
    module = { ... };
  };
  output  = { ... };
  schema  = { ... };
  traits  = { ... };
  options = { ... };
  extend  = { ... } -> { ... };
}
```

## Top-level Options

Available in every nixy-level `.nix` file:

| Option | Type | Description |
|--------|------|-------------|
| `schema` | deep-merged attrset | Option declarations |
| `traits` | attrsOf deferredModule | Named modules (key = trait name) |
| `nodes` | lazy attrsOf submodule | Target definitions |
| `output` | deep-merged attrset | User data passed through to the result |

Nodes use a lazy attribute set type — accessing one node does not force evaluation of others.

## Node Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `traits` | list of strings | `[ ]` | Trait names to activate |
| `schema` | submodule with freeform | `{ }` | Values matching global schema; undeclared keys produce a warning |
| `includes` | list of raw | `[ ]` | Extra modules |

## output

Any nixy-level module can write to `output`:

```nix
{ config, lib, ... }:
{
  output.meta = lib.mapAttrs (_: n: { inherit (n) schema traits; }) config.nodes;
}
```

Access via `cluster.output.meta`.

## extend

Incrementally extend with additional imports layered on top:

```nix
cluster.extend {
  imports ? [ ];
  args ? { };
  exclude ? null;
  disabledModules ? [ ];
}
```

Returns a new result with the same shape. `lib` is inherited from the original call. New `args` are deep-merged with `lib.recursiveUpdate`. New `disabledModules` are appended to existing ones.

Uses `extendModules` internally — this is incremental, not a full re-evaluation.

## disabledModules

Disable specific modules from evaluation. Accepts the same values as the module system's `disabledModules`: file path strings, path values, or `{ key = "..."; }` attrsets.

Traits loaded by nixy carry a stable key of the form `"nixy/trait:<traitName>"`. To disable a specific trait across all nodes:

```nix
cluster.extend {
  disabledModules = [ { key = "nixy/trait:ssh"; } ];
}
```

For path-based modules, use the file path:

```nix
nixy.eval {
  inherit (nixpkgs) lib;
  imports = [ ./. ];
  disabledModules = [ "/absolute/path/to/module.nix" ];
}
```

## Module Arguments

**nixy-level** (schema/trait/node definition files): `lib` plus everything in `args`.

**Node-level** (inside traits and includes): nixy injects nothing. Pass what you need via `specialArgs` in the target builder. Standard module args (`config`, `pkgs`, `lib`, …) come from the target builder.

## Scanning Defaults

Excluded by default: names starting with `_` or `.`, `flake.nix`, `default.nix`.
