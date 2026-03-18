{
  nodes.server = {
    traits = [ "base" "systemd-boot" "ssh" ];
    schema.base.hostName = "server";
    schema.base.user = "admin";
    schema.base.domain = "infra.local";
    schema.ssh.port = 2222;
    schema.ssh.permitRoot = true;
    includes = [
      {
        fileSystems."/" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
        };
        fileSystems."/boot" = {
          device = "/dev/disk/by-label/boot";
          fsType = "vfat";
          options = [ "fmask=0077" "dmask=0077" ];
        };
        networking.firewall.allowedTCPPorts = [ 2222 ];
      }
    ];
  };
}
