{
  description = "nixy: A minimal NixOS/Darwin/Home Manager framework";

  outputs =
    { self }:
    {
      mkFlake = import ./mkFlake.nix;
      mkConfiguration = import ./mkConfiguration.nix;
    };
}
