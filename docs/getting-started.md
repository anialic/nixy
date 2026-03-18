# Getting Started

## Install

```bash
nix flake init -t github:cuskiy/nixy#minimal
```

Creates five files:

- `flake.nix` — wires nixy into `nixosConfigurations`
- `base.nix` — schema defaults and traits
- `ssh.nix` — ssh schema and trait
- `my-nixos.nix` — a node definition
- `server.nix` — a second node with overrides

## Build

```bash
nix build .#nixosConfigurations.my-nixos.config.system.build.toplevel
```

## How It Works

`nixy.eval` scans your directory for `.nix` files, collects `schema`, `traits`, and `nodes`, then produces one module per node.

```
your-config/
├── flake.nix
├── base.nix           # schema + traits
├── ssh.nix            # schema + trait
├── my-nixos.nix       # node
└── server.nix         # node with overrides
```

Each node carries `schema`, `traits`, and `module`:

```nix
builtins.mapAttrs (name: node:
  nixpkgs.lib.nixosSystem {
    system = node.schema.base.system;
    modules = [ node.module ];
    specialArgs = { inherit name; inherit (node) schema; };
  }
) cluster.nodes
```

## Next

- [Guide](guide.md) — schema, traits, nodes in detail
- [API](api.md) — parameters and return shape
- [Advanced](advanced.md) — composition and extend
