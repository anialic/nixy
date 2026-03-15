# Getting Started

## Install

```bash
nix flake init -t github:cuskiy/nixy#minimal
```

This creates three files:

- `flake.nix` — wires nixy into `nixosConfigurations`
- `base.nix` — schema options and a `base` trait
- `my-nixos.nix` — a node using the `base` trait

## Build

```bash
nix build .#nixosConfigurations.my-nixos.config.system.build.toplevel
```

## How It Works

`nixy.eval` scans your directory for `.nix` files, collects all `schema`, `traits`, and `nodes` definitions, then produces one module per node.

```
your-config/
├── flake.nix
├── base.nix           # schema + traits
├── ssh.nix            # schema + traits
└── my-nixos.nix       # node
```

Each node result carries `schema`, `traits`, and `module`. You pass what you need into the target builder:

```nix
nixpkgs.lib.mapAttrs (name: node:
  nixpkgs.lib.nixosSystem {
    system = node.schema.base.system;
    modules = [ node.module ];
    specialArgs = { inherit name; inherit (node) schema; };
  }
) cluster.nodes
```

## Next Steps

- [Guide](guide.md) — schema, traits, nodes in detail
- [API](api.md) — `nixy.eval` parameters and return shape
- [Advanced](advanced.md) — output, helpers, composition
