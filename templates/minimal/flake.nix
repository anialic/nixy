{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixy.url = "github:cuskiy/nixy";
  };

  outputs =
    { nixpkgs, nixy, ... }@inputs:
    let
      cluster = nixy.eval {
        imports = [ ./. ];
        args = { inherit inputs; };
      };
    in
    {
      nixosConfigurations = builtins.mapAttrs (
        name: node:
        nixpkgs.lib.nixosSystem {
          system = node.schema.base.system;
          modules = [ node.module ];
          specialArgs = {
            inherit name;
            inherit (node) schema;
          };
        }
      ) cluster.nodes;
    };
}
