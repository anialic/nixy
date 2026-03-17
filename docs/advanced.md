# Advanced

## Schema Helpers

For large configurations, `lib.mkOption` verbosity adds up. Define helpers outside the scanned directory (or exclude them):

```nix
# helpers.nix
{ lib }:
let
  mkOpt = type: default:
    lib.mkOption { type = lib.types.nullOr type; inherit default; };
  mkReq = type: lib.mkOption { inherit type; };
in
{
  inherit mkOpt mkReq;
  mkStr     = mkOpt lib.types.str;
  mkBool    = mkOpt lib.types.bool;
  mkInt     = mkOpt lib.types.int;
  mkPort    = mkOpt lib.types.port;
  mkPath    = mkOpt lib.types.path;
  mkLines   = mkOpt lib.types.lines;
  mkPackage = mkOpt lib.types.package;
  mkRaw     = mkOpt lib.types.raw;
  mkEnum    = values: mkOpt (lib.types.enum values);
  mkList    = elem:   mkOpt (lib.types.listOf elem);
  mkAttrsOf = val:    mkOpt (lib.types.attrsOf val);
  mkEither  = a: b:   mkOpt (lib.types.either a b);
  mkOneOf   = ts:     mkOpt (lib.types.oneOf ts);
  mkSub = opts: lib.mkOption {
    type = lib.types.submodule { options = opts; };
    default = { };
  };
  mkSubList = opts: lib.mkOption {
    type = lib.types.listOf (lib.types.submodule { options = opts; });
    default = [ ];
  };
}
```

Pass them via `args`:

```nix
# flake.nix
let
  helpers = import ./helpers.nix { inherit (nixpkgs) lib; };
  cluster = nixy.eval {
    inherit (nixpkgs) lib;
    imports = [ ./. ];
    args = { inherit inputs; } // helpers;
  };
```

Then use directly in nixy-level files:

```nix
{ mkStr, mkBool, mkPort, mkEnum, mkReq, mkSubList, lib, ... }:
{
  schema.base = {
    system   = mkStr "x86_64-linux";
    hostName = mkStr null;
    user     = mkStr null;
    timeZone = mkStr "UTC";
    target   = mkEnum [ "nixos" "iso" "darwin" ] "nixos";
  };

  schema.ssh = {
    port           = mkPort 22;
    permitRoot     = mkBool false;
    authorizedKeys = mkList lib.types.str null;
  };

  schema.net = {
    ip      = mkStr null;
    gateway = mkStr null;
    dns     = mkList lib.types.str null;
    iface   = mkStr null;
  };

  schema.users = mkSubList {
    name   = mkReq lib.types.str;
    groups = mkList lib.types.str [ ];
    shell  = mkStr null;
    keys   = mkList lib.types.str [ ];
  };
}
```

---

## Custom Output

`output` is a deep-merged attrset available to any nixy-level module. Use it for cluster-level data shared across traits or exposed to external tools.

### Cross-node references

Build a metadata view that traits consume:

```nix
# meta.nix
{ config, lib, ... }:
{
  output.meta = lib.mapAttrs (_: n: {
    inherit (n) schema traits;
  }) config.nodes;
}
```

Wire it into `specialArgs`:

```nix
mkSystem = name: node:
  lib.nixosSystem {
    system = node.schema.base.system;
    modules = [ node.module ];
    specialArgs = {
      inherit name;
      inherit (node) schema;
      meta = cluster.output.meta;
    };
  };
```

Traits can then reference other nodes:

```nix
traits.wireguard-peer = { schema, meta, ... }: {
  networking.wireguard.interfaces.wg0.peers = map (name: {
    publicKey  = meta.${name}.schema.wireguard.publicKey;
    allowedIPs = [ "${meta.${name}.schema.net.ip}/32" ];
    endpoint   = "${meta.${name}.schema.net.ip}:${toString meta.${name}.schema.wireguard.port}";
  }) schema.wireguard.peers;
};
```

### Deployment inventory

`output` values are plain Nix — serialize them for use outside NixOS:

```nix
{ config, lib, ... }:
{
  output.inventory = lib.mapAttrs (_: n: {
    ip     = n.schema.net.ip;
    user   = n.schema.base.user;
    system = n.schema.base.system;
    tags   = n.traits;
  }) config.nodes;
}
```

```nix
packages.inventory = pkgs.writeText "inventory.json"
  (builtins.toJSON cluster.output.inventory);
```

### Multi-target routing

```nix
let
  byTarget = t:
    lib.filterAttrs (_: n: (n.schema.base.target or "nixos") == t) cluster.nodes;

  mkNixos = nodes:
    lib.mapAttrs (name: n:
      lib.nixosSystem {
        system = n.schema.base.system;
        modules = [ n.module ];
        specialArgs = { inherit name inputs; inherit (n) schema; meta = cluster.output.meta; };
      }
    ) nodes;
in
{
  nixosConfigurations = mkNixos (byTarget "nixos");
}
```

---

## Composition with extend

`extend` adds imports incrementally using `extendModules`. `lib` is inherited; new `args` are deep-merged with `lib.recursiveUpdate`.

### Library + consumer

```nix
# shared library flake
outputs = { self }: {
  base = import ./nix/eval.nix {
    inherit lib;
    imports = [ ./base ];
  };
};
```

```nix
# consumer flake
let
  cluster = inputs.mylib.base.extend {
    imports = [ ./. ];
    args = { inherit inputs; };
  };
```

### Layered environments

```nix
base = nixy.eval { inherit lib; imports = [ ./base ]; args = { inherit inputs; }; };
prod = base.extend { imports = [ ./prod ]; args = { env = "prod"; }; };
dev  = base.extend { imports = [ ./dev  ]; args = { env = "dev";  }; };
```

### Overriding exclude

Reset to default:

```nix
cluster.extend {
  imports = [ ./extra ];
  exclude = null;
}
```

Replace entirely:

```nix
cluster.extend {
  imports = [ ./extra ];
  exclude = { name, ... }: lib.hasSuffix ".test.nix" name;
}
```
