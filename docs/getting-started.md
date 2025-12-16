# Getting Started

## Installation

Initialize a new project from a template:

```bash
nix flake init -t github:anialic/nixy#minimal
```

Available templates:
- `minimal` - Single NixOS machine
- `multi-platform` - NixOS + Darwin + Home Manager
- `deploy-rs` - Remote deployment
- `without-flakes` - Traditional setup

## Project Structure

```
my-config/
├── flake.nix
├── modules/
│   └── base.nix
└── nodes/
    └── alice.nix
```

## Basic Configuration

**flake.nix**
```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nixy.url = "github:anialic/nixy";

  outputs = { nixpkgs, nixy, ... }@inputs: nixy.mkFlake {
    inherit nixpkgs;
    imports = [ ./modules ./nodes ];
    args = { inherit inputs; };
  };
}
```

**modules/base.nix**
```nix
{ mkStr, lib, ... }:
{
  modules.base = {
    target = "nixos";
    options.hostName = mkStr null;
    module = { node, ... }: {
      networking.hostName = node.base.hostName;
      system.stateVersion = "25.11";
    };
  };
}
```

**nodes/alice.nix**
```nix
{
  nodes.alice = {
    system = "x86_64-linux";
    base.enable = true;
    base.hostName = "alice";
  };
}
```

## Building

```bash
nixos-rebuild switch --flake .#alice
```
