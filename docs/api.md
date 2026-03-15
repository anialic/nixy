# API Reference

## nixy.eval

```nix
nixy.eval {
  lib;
  imports ? [ ];
  args ? { };
  exclude ? null;
}
```

| Parameter | Description |
|-----------|-------------|
| `lib` | Nixpkgs `lib` |
| `imports` | Directories, `.nix` files, functions, attrsets, or lists thereof |
| `args` | Extra arguments available in nixy-level modules via `specialArgs` |
| `exclude` | `{ name, path } -> bool` — return `true` to skip a file during scanning |

**Returns:**

```nix
{
  nodes.<name> = {
    schema = { ... };
    traits = [ ... ];
    module = { ... };
  };
  output = { ... };
  extend = { ... } -> { ... };
}
```

## Top-level Options

Available in every nixy-level `.nix` file:

| Option | Type | Description |
|--------|------|-------------|
| `schema` | deep-merged attrset | Option declarations |
| `traits` | attrsOf raw | Named modules (key = trait name) |
| `nodes` | lazyAttrsOf submodule | Target definitions |
| `output` | deep-merged attrset | User data passed through to the result |

Nodes use a lazy attribute set type — accessing one node does not force evaluation of others.

## Node Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `traits` | list of strings | `[ ]` | Trait names to activate |
| `schema` | submodule | `{ }` | Values matching global schema |
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

Re-evaluate with additional imports layered on top:

```nix
cluster.extend {
  imports ? [ ];
  args ? { };
  exclude ? null;
}
```

Returns a new result with the same shape. `lib` is inherited from the original call. New `args` are merged with `//`. This is a full re-evaluation, not incremental.

## Module Arguments

**nixy-level** (schema/trait/node definition files): `lib` plus everything in `args`.

**Node-level** (inside traits and includes): nixy injects nothing. Pass what you need via `specialArgs` in the target builder. Standard module args (`config`, `pkgs`, `lib`, …) come from the target builder.

## Scanning Defaults

Excluded by default: names starting with `_` or `.`, `flake.nix`, `default.nix`.
