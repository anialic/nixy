# Guide

## Schema

A pure default-value tree. Non-attrset values are leaves; attrsets are subtrees.

```nix
{ ... }:
{
  schema.ssh = {
    port = 22;
    permitRoot = false;
  };

  schema.base = {
    system = "x86_64-linux";
    hostName = "nixos";
  };
}
```

Multiple files can contribute to the same schema tree — subtrees merge, duplicate leaves error.

## Traits

A trait is a named module. The value can be a function, an attrset, or a path.

```nix
traits.ssh = { schema, config, pkgs, ... }: {
  services.openssh = {
    enable = true;
    ports = [ schema.ssh.port ];
    settings.PermitRootLogin = if schema.ssh.permitRoot then "yes" else "no";
  };
};
```

Same-name traits from different files are merged — both definitions are included when activated.

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

**traits** — trait names to activate. Unknown names error.

**schema** — overrides merged with global defaults: both attrsets → recurse, otherwise node value wins. Nodes can add keys not in the global schema.

**includes** — extra NixOS modules appended after trait modules.

## Wiring

Each node result carries `schema`, `traits`, and `module`:

```nix
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
}
```

You control what names are available inside traits via `specialArgs`.

## Multi-platform

Filter nodes by schema values:

```nix
let
  cluster = nixy.eval {
    imports = [ ./. ];
    args = { inherit inputs; };
  };
  byTarget = t: builtins.removeAttrs cluster.nodes
    (builtins.filter (n: (cluster.nodes.${n}.schema.base.target or "nixos") != t)
      (builtins.attrNames cluster.nodes));
in {
  nixosConfigurations = builtins.mapAttrs (name: node:
    nixpkgs.lib.nixosSystem {
      system = node.schema.base.system;
      modules = [ node.module ];
      specialArgs = { inherit name; inherit (node) schema; };
    }
  ) (byTarget "nixos");
}
```

## Scanning

`nixy.eval` resolves `imports` recursively:

- **Directories** — scanned for `.nix` files recursively
- **Symlinks** — followed (directories scanned, `.nix` files loaded)
- **Files** (`.nix`) — loaded directly
- **Functions / attrsets** — passed through as inline modules
- **Lists** — flattened

Excluded by default: names starting with `_` or `.`, `flake.nix`, `default.nix`.

Override with `exclude`:

```nix
nixy.eval {
  imports = [ ./. ];
  exclude = { name, ... }: name == "test.nix";
}
```
