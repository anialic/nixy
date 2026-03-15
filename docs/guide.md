# Guide

nixy organizes configuration around three concepts: **schema** declares options, **traits** implement behavior, and **nodes** define targets.

## Schema

Declare options with `lib.mkOption`. Multiple files can contribute to the same schema tree — they are deep-merged.

```nix
{ lib, ... }:
{
  schema.ssh = {
    port = lib.mkOption {
      type = lib.types.port;
      default = 22;
    };
    permitRoot = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };
  };

  schema.base = {
    system = lib.mkOption {
      type = lib.types.str;
      default = "x86_64-linux";
    };
    hostName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
  };
}
```

## Traits

A trait is a named behavior unit. The key is the trait name, the value is a module.

Arguments available inside traits depend on what you pass via `specialArgs` in the target builder — nixy itself does not inject anything:

```nix
traits.ssh = { schema, config, pkgs, ... }: {
  services.openssh = {
    enable = true;
    ports = [ schema.ssh.port ];
    settings.PermitRootLogin = if schema.ssh.permitRoot then "yes" else "no";
  };
};
```

## Nodes

Each node has three fields:

```nix
{
  nodes.server = {
    traits = [ "base" "ssh" ];
    schema.ssh.port = 2222;
    includes = [
      { services.fail2ban.enable = true; }
      ./hardware-configuration.nix
    ];
  };
}
```

**traits** — Trait names to activate. Unknown names are an error.

**schema** — Type-checked values matching global schema declarations. Unset values use defaults. Schema values are exposed in the result alongside the module.

**includes** — Extra modules appended after trait modules.

## Wiring Nodes

Each node in the result carries `schema`, `traits`, and `module`:

```nix
let
  cluster = nixy.eval {
    inherit (nixpkgs) lib;
    imports = [ ./. ];
    args = { inherit inputs; };
  };
in {
  nixosConfigurations = lib.mapAttrs (name: node:
    lib.nixosSystem {
      system = node.schema.base.system;
      modules = [ node.module ];
      specialArgs = { inherit name; inherit (node) schema; };
    }
  ) cluster.nodes;
}
```

This keeps nixy out of the target module system's namespace. You control exactly what names are available inside traits.

## Multi-platform

Route nodes to different builders by filtering on schema values:

```nix
let
  cluster = nixy.eval {
    inherit (nixpkgs) lib;
    imports = [ ./. ];
    args = { inherit inputs; };
  };
  byTarget = t: lib.filterAttrs (_: n: (n.schema.base.target or "nixos") == t) cluster.nodes;
  mkArgs = name: node: { inherit name; inherit (node) schema; inherit inputs; };
in {
  nixosConfigurations = lib.mapAttrs (name: node:
    lib.nixosSystem {
      system = node.schema.base.system;
      modules = [ node.module ];
      specialArgs = mkArgs name node;
    }
  ) (byTarget "nixos");

  darwinConfigurations = lib.mapAttrs (name: node:
    inputs.darwin.lib.darwinSystem {
      system = node.schema.base.system;
      modules = [ node.module ];
      specialArgs = mkArgs name node;
    }
  ) (byTarget "darwin");
}
```

## Imports and Scanning

`nixy.eval` scans `imports` recursively:

- **Directories** — scanned for `.nix` files recursively
- **Files** (`.nix`) — loaded directly
- **Functions** and **attrsets** — passed through as inline modules
- **Lists** — flattened

By default, files starting with `_` or `.`, plus `flake.nix` and `default.nix`, are excluded. Override with `exclude`:

```nix
nixy.eval {
  inherit (nixpkgs) lib;
  imports = [ ./. ];
  exclude = { name, ... }: name == "test.nix";
}
```

## Cross-node References

Traits can read other nodes' data via `output` passed through `specialArgs`:

```nix
traits.client = { output, ... }: {
  services.myApp.serverHost = output.meta.server.schema.net.ip;
};
```

See [Advanced](advanced.md) for the `output` pattern.

## Error Tracking

nixy tags each trait and include module with location information. When evaluation fails, the trace includes the source (trait name or include index) and node name.
