# Nixy

**nixy** is a module builder that helps structure large Nix configurations.

It models configuration around three concepts:

* **Schema** — Typed options with defaults, deep-merged across files.
* **Traits** — Named behavior units that turn schema values into configuration.
* **Nodes** — Targets that select traits, override schema values, and produce modules.

The result is standard Nix modules, fully compatible with `lib.evalModules` and `lib.nixosSystem`.

## Quick Start

```bash
nix flake init -t github:cuskiy/nixy#minimal
```

## Example

```nix
# base.nix
{ lib, ... }:
{
  schema.ssh.port = lib.mkOption {
    type = lib.types.port;
    default = 22;
  };

  traits.ssh = { schema, ... }: {
    services.openssh.enable = true;
    services.openssh.ports = [ schema.ssh.port ];
  };
}
```

```nix
# nodes.nix
{
  nodes.server = {
    traits = [ "ssh" ];
    schema.ssh.port = 2222;
  };
}
```

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixy.url = "github:cuskiy/nixy";
  };

  outputs = { nixpkgs, nixy, ... }@inputs:
    let
      cluster = nixy.eval {
        inherit (nixpkgs) lib;
        imports = [ ./. ];
        args = { inherit inputs; };
      };
    in {
      nixosConfigurations = nixpkgs.lib.mapAttrs (name: node:
        nixpkgs.lib.nixosSystem {
          system = node.schema.base.system;
          modules = [ node.module ];
          specialArgs = { inherit name; inherit (node) schema; };
        }
      ) cluster.nodes;
    };
}
```

## Documentation

- [Getting Started](docs/getting-started.md)
- [Guide](docs/guide.md)
- [API Reference](docs/api.md)
- [Advanced](docs/advanced.md)

## License

Apache-2.0
