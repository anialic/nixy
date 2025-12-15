{
  nodes.alice = {
    system = "aarch64-linux";
    base.enable = true;
    base.hostName = "alice";
    base.user = "alice";
    extraModules = [
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
