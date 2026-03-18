# Advanced

## Cross-node References

Build cross-node data outside nixy, pass it via `specialArgs`:

```nix
let
  cluster = nixy.eval {
    imports = [ ./. ];
    args = { inherit inputs; };
  };
  meta = builtins.mapAttrs (_: n: {
    inherit (n) schema traits;
  }) cluster.nodes;
in {
  nixosConfigurations = builtins.mapAttrs (name: node:
    nixpkgs.lib.nixosSystem {
      system = node.schema.base.system;
      modules = [ node.module ];
      specialArgs = { inherit name meta; inherit (node) schema; };
    }
  ) cluster.nodes;
}
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

## Deployment Inventory

Serialize node data for external tools:

```nix
packages.x86_64-linux.inventory = let
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
  inv = builtins.mapAttrs (_: n: {
    ip     = n.schema.net.ip;
    user   = n.schema.base.user;
    system = n.schema.base.system;
    tags   = n.traits;
  }) cluster.nodes;
in pkgs.writeText "inventory.json" (builtins.toJSON inv);
```

## Composition with extend

`extend` layers additional imports on top. `args` are shallow-merged (`//`).

### Library + consumer

```nix
# shared library flake
outputs = { self }: {
  base = import ./nix/eval.nix {
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
base = nixy.eval { imports = [ ./base ]; args = { inherit inputs; }; };
prod = base.extend { imports = [ ./prod ]; args = { env = "prod"; }; };
dev  = base.extend { imports = [ ./dev  ]; args = { env = "dev";  }; };
```

### Overriding exclude

A new `exclude` in `extend` applies only to the new imports — previously resolved paths are not re-scanned. Passing `args` triggers a full re-evaluation of all modules but still uses the already-resolved file list.

```nix
cluster.extend {
  imports = [ ./extra ];
  exclude = null;
}
```

```nix
cluster.extend {
  imports = [ ./extra ];
  exclude = { name, ... }: name == "test.nix";
}
```

## Trait Composition

Same-name traits from different files are merged — both included when activated:

```nix
# library: base-ssh.nix
{
  traits.ssh = { schema, ... }: {
    services.openssh.enable = true;
    services.openssh.ports = [ schema.ssh.port ];
  };
}
```

```nix
# consumer: hardened-ssh.nix
{
  traits.ssh = {
    services.openssh.settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
}
```

## Trait Groups

Use plain Nix:

```nix
# groups.nix
{
  webServer = [ "base" "systemd-boot" "ssh" "nginx" "certbot" ];
  dbServer  = [ "base" "systemd-boot" "ssh" "postgresql" ];
}
```

```nix
# nodes.nix
let groups = import ./groups.nix; in
{
  nodes.web-1 = {
    traits = groups.webServer;
    schema.base.hostName = "web-1";
  };
  nodes.db-1 = {
    traits = groups.dbServer;
    schema.base.hostName = "db-1";
  };
}
```
