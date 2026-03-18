{
  description = "Structured configuration for Nix fleets";

  outputs =
    { self }:
    {
      eval = import ./nix/eval.nix;

      templates.minimal = {
        description = "Single NixOS machine";
        path = ./templates/minimal;
      };
    };
}
