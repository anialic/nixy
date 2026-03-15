{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixy.url = "github:cuskiy/nixy";
  };

  outputs =
    { nixpkgs, nixy, ... }@inputs:
    let
      cluster = nixy.eval {
        inherit (nixpkgs) lib;
        imports = [ ./. ];
        args = { inherit inputs; };
      };
      mkSystem =
        name: node:
        nixpkgs.lib.nixosSystem {
          system = node.schema.base.system;
          modules = [ node.module ];
          specialArgs = {
            inherit name;
            inherit (node) schema;
          };
        };
    in
    {
      nixosConfigurations = nixpkgs.lib.mapAttrs mkSystem cluster.nodes;
    };
}
