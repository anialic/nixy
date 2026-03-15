{
  nodes.my-nixos = {
    traits = [ "base" ];
    schema.base.hostName = "my-nixos";
    schema.base.user = "alice";
    includes = [
      {
        fileSystems."/" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
        };
        fileSystems."/boot" = {
          device = "/dev/disk/by-label/boot";
          fsType = "vfat";
          options = [
            "fmask=0077"
            "dmask=0077"
          ];
        };
      }
    ];
  };
}
