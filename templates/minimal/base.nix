{ lib, ... }:
{
  schema.base = {
    system = lib.mkOption {
      type = lib.types.str;
      default = "x86_64-linux";
    };
    hostName = lib.mkOption {
      type = lib.types.str;
      default = "nixos";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "alice";
    };
    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "UTC";
    };
  };

  traits.base =
    { schema, pkgs, ... }:
    {
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      networking.hostName = schema.base.hostName;
      time.timeZone = schema.base.timeZone;
      users.users.${schema.base.user} = {
        isNormalUser = true;
        extraGroups = [ "wheel" "networkmanager" ];
        initialPassword = "changeme";
      };
      system.stateVersion = "26.05";
      nix.settings.experimental-features = [ "nix-command" "flakes" ];
    };
}
