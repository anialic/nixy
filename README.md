# Nixy

Structured configuration for Nix fleets.

Three concepts:

- **Schema** — default-value tree shared across the configuration
- **Traits** — named modules that read schema values and produce configuration
- **Nodes** — targets that select traits, override schema, and yield ready-to-use modules

Output is standard NixOS modules, compatible with `nixosSystem`.

## Quick Start

```bash
nix flake init -t github:cuskiy/nixy#minimal
```

## Example

```nix
# base.nix
{ ... }:
{
  schema.base = {
    system = "x86_64-linux";
    hostName = "nixos";
  };

  schema.ssh.port = 22;

  traits.ssh = { schema, ... }: {
    services.openssh.enable = true;
    services.openssh.ports = [ schema.ssh.port ];
  };
}
```

```nix
# server.nix
{
  nodes.server = {
    traits = [ "ssh" ];
    schema.base.hostName = "server";
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
        imports = [ ./. ];
        args = { inherit inputs; };
      };
    in {
      nixosConfigurations = builtins.mapAttrs (name: node:
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
