{
  lib,
  config,
  inputs,
  ...
}:
let
  deployNodes = lib.filterAttrs (_: n: n.deploy.enable or false) config.nodes;
in
{
  flake.deploy.nodes = lib.mapAttrs (
    name: node:
    let
      cfg = config.flake.nixosConfigurations.${name};
    in
    {
      hostname = node.deploy.hostname;
      sshUser = node.deploy.sshUser;
      profiles.system = {
        user = "root";
        path = inputs.deploy-rs.lib.${node._system}.activate.nixos cfg;
      };
    }
  ) deployNodes;
}
