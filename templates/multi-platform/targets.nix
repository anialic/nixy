{ inputs, nixpkgs, ... }:
{
  targets.darwin = {
    instantiate =
      {
        system,
        modules,
        specialArgs,
      }:
      inputs.nix-darwin.lib.darwinSystem { inherit system modules specialArgs; };
    output = "darwinConfigurations";
  };

  targets.home = {
    instantiate =
      {
        system,
        modules,
        specialArgs,
      }:
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        modules = modules;
        extraSpecialArgs = specialArgs;
      };
    output = "homeConfigurations";
  };
}
