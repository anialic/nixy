{
  nixpkgs,
  imports ? [ ],
  args ? { },
  exclude ? null,
}:
let
  nixyLib = import ./lib.nix { inherit (nixpkgs) lib; };
in
nixyLib.eval {
  inherit
    nixpkgs
    args
    exclude
    imports
    ;
  inputs = { inherit nixpkgs; };
}
