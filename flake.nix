{
  description = "nixy: A minimal NixOS/Darwin/Home Manager framework";

  outputs =
    { self }:
    {
      mkFlake = import ./lib/mkFlake.nix;
      mkConfiguration = import ./lib/mkConfiguration.nix;
    };
}
