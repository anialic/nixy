{ ... }:
{
  schema.base = {
    system = "x86_64-linux";
    hostName = "nixos";
    user = "alice";
    timeZone = "UTC";
    domain = null;
  };

  traits.base =
    { schema, pkgs, lib, ... }:
    {
      networking.hostName = schema.base.hostName;
      networking.domain = lib.mkIf (schema.base.domain != null) schema.base.domain;
      time.timeZone = schema.base.timeZone;
      users.users.${schema.base.user} = {
        isNormalUser = true;
        extraGroups = [ "wheel" "networkmanager" ];
        initialPassword = "changeme";
      };
      system.stateVersion = "26.05";
      nix.settings.experimental-features = [ "nix-command" "flakes" ];
    };

  traits.systemd-boot = {
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
  };
}
