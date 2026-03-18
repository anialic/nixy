# API Reference

## nixy.eval

```nix
nixy.eval {
  imports ? [ ];
  args ? { };
  exclude ? null;
}
```

| Parameter | Description |
|-----------|-------------|
| `imports` | Directories, `.nix` files, functions, attrsets, or lists thereof |
| `args` | Arguments passed to nixy-level module functions |
| `exclude` | `{ name, path } -> bool` — return `true` to skip a file |

**Returns:**

```nix
{
  nodes.<n> = {
    schema  = { ... };
    traits  = [ ... ];
    module  = { _file = "<nixy:name>"; imports = [ ... ]; };
  };
  schema = { ... };
  traits = { ... };
  extend = { ... } -> { ... };
}
```

## Module Keys

Available in every nixy-level `.nix` file:

| Key | Description |
|-----|-------------|
| `schema` | Default-value tree. Attrset = subtree, anything else = leaf. Merged across files; leaf conflicts error. |
| `traits` | Named modules. Same name from multiple files → both kept. |
| `nodes` | Target definitions. Duplicate node names error. |

## Node Fields

| Field | Default | Description |
|-------|---------|-------------|
| `traits` | `[ ]` | Trait names to activate |
| `schema` | `{ }` | Overrides merged with global schema defaults |
| `includes` | `[ ]` | Extra NixOS modules appended after traits |

## extend

```nix
cluster.extend {
  imports ? [ ];
  args ? { };
  exclude ? null;
}
```

Returns a new result with the same shape. Incremental — only new modules are loaded and merged into existing state. Passing `args` triggers a full re-evaluation (module functions may return different values).

## Module Arguments

**nixy-level** (schema/trait/node files): everything in `args`.

**Node-level** (inside traits and includes): controlled by `specialArgs` in the target builder. Standard module args (`config`, `pkgs`, `lib`, …) come from the target builder.

## Scanning Defaults

Excluded: names starting with `_` or `.`, `flake.nix`, `default.nix`.
