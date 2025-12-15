{
  description = "nixy: A minimal NixOS/Darwin/Home Manager framework";

  outputs =
    { self }:
    {
      templates = {
        minimal = {
          description = ''
            Minimal configuration.
          '';
          path = ./templates/minimal;
        };
        multi-platform = {
          description = ''
            Use Standalone Home-Manager and nix-darwin.
          '';
          path = ./templates/multi-platform;
        };
        deploy-rs = {
          description = ''
            Use deploy-rs.
          '';
          path = ./templates/deploy-rs;
        };
        without-flakes = {
          description = ''
            Traditional configuration. You need `nix-build -A nixosConfigurations.<hostname>.config.system.build.toplevel` and `sudo bash ./result/bin/switch-to-configuration switch` for it to take effect.
          '';
          path = ./templates/without-flakes;
        };
      };

      mkFlake = import ./lib/mkFlake.nix;
      mkConfiguration = import ./lib/mkConfiguration.nix;
    };
}
