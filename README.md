<div align="center">
  <a href="#">
    <img src="https://raw.githubusercontent.com/anialic/nixy/main/.github/logo.svg" width="200" alt="nixy logo">
    <h1>Nixy</h1>
  </a>
</div>

## Key Features

All configuration lives in `nodes.*`. One node is one machine:
```nix
nodes.server = {
  system = "x86_64-linux";
  base.enable = true;
  base.hostName = "server";
  ssh.enable = true;
};
```

**How it works**

1. Scans all `.nix` files under `imports`, collects definitions
2. Each module gets an `enable` option under `nodes.<n>.<module>.enable`
3. Only `enable = true` modules get imported; disabled modules don't exist in final config
4. Outputs standard `nixosConfigurations` / `darwinConfigurations` / `homeConfigurations`

## Usage

**Flake mode**
```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nixy.url = "github:anialic/nixy";

  outputs = { nixpkgs, nixy, ... }@inputs: nixy.mkFlake {
    inherit nixpkgs;
    imports = [ ./. ];
    args = { inherit inputs; };
  };
}
```

**Traditional mode**
```nix
let
  lock = builtins.fromJSON (builtins.readFile ./inputs.lock);
  fetch = name: builtins.fetchTarball lock.${name};
  nixy = import (fetch "nixy");
  nixpkgsSrc = fetch "nixpkgs";
  pkgs = import nixpkgsSrc { };
  nixpkgs = {
    inherit (pkgs) lib;
    legacyPackages.${builtins.currentSystem} = pkgs;
  };
in
nixy.mkConfiguration {
  inherit nixpkgs;
  imports = [ ./. ];
}
```

## API

**mkFlake / mkConfiguration**
```nix
{
  nixpkgs,          # required
  imports ? [ ],    # directories or files to scan
  args ? { },       # passed to all modules
  exclude ? null,   # { name, path }: bool
}
```

Default exclude skips _*, .*, default.nix and flake.nix:

```nix
exclude = { name, ... }:
  let c = builtins.substring 0 1 name;
  in c == "_" || c == "." || name == "flake.nix" || name == "default.nix";
```

**Top-level options**

| Option | Description |
|--------|-------------|
| `systems` | List of systems (default: linux + darwin, x86_64 + aarch64) |
| `modules.*` | Module definitions |
| `nodes.*` | Node definitions |
| `targets.*` | Target builders (nixos built-in) |
| `rules` | Assertions before build |
| `perSystem` | Per-system outputs (packages, devShells, etc.) |
| `flake.*` | Extra flake outputs |

**modules.\<name\>**

| Field | Description |
|-------|-------------|
| `target` | `"nixos"`, `"darwin"`, `"home"`, or `null` (all) |
| `requires` | Dependencies, checked at build time |
| `options` | Option declarations |
| `module` | NixOS/Darwin/HM module |

**nodes.\<name\>**

| Field | Description |
|-------|-------------|
| `system` | Required, e.g. `"x86_64-linux"` |
| `target` | Optional, inferred from system |
| `<module>.enable` | Enable a module |
| `<module>.<option>` | Set module options |
| `extraModules` | Additional NixOS/Darwin/HM modules |
| `instantiate` | Custom builder |

**Framework module arguments**

| Arg | Description |
|-----|-------------|
| `lib` | nixpkgs.lib |
| `nixpkgs` | nixpkgs input |
| `config` | Framework config |
| `pkgsFor` | `system -> pkgs` |
| `mkStr`, `mkBool`, ... | Option helpers |

**NixOS/Darwin/HM module arguments**

| Arg | Description |
|-----|-------------|
| `node` | Current node config |
| `nodes` | All node configs |
| `name` | Node name |
| `system` | System string |
| `inputs` | All inputs |

**Built-in apps**
```bash
nix run .#allOptions    # list all modules and options
nix run .#allNodes      # list all nodes
nix run .#checkOptions  # verify all options have defaults
nix run .#graph         # show dependency graph (mermaid)
```

## Examples

- [Minimal NixOS](https://gist.github.com/anialic/2ea7a1e2d3926a5704897b60a63a694a)
- [Multi-host](https://gist.github.com/anialic/0570c49ad19b128c1377da052dc0c4c8)
- [With deploy-rs](https://gist.github.com/anialic/b8dc7ff63b7ac01932007db3b4baa67b)
- [Without flakes](https://gist.github.com/anialic/9b244cae11b0fe57a6b01439d4010ffc)
