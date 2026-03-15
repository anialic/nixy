{
  lib,
  imports ? [ ],
  args ? { },
  exclude ? null,
}:

let
  defaultExclude =
    { name, ... }:
    let c = builtins.substring 0 1 name; in
    c == "_" || c == "." || name == "flake.nix" || name == "default.nix";

  excludeFn =
    if exclude == null then defaultExclude
    else if builtins.isFunction exclude then exclude
    else throw "[nixy] 'exclude' must be a function";

  scanDir =
    dir:
    lib.concatMap (
      { name, value }:
      let path = dir + "/${name}"; in
      if excludeFn { inherit name path; } then [ ]
      else if value == "directory" then scanDir path
      else if value == "regular" && lib.hasSuffix ".nix" name then [ path ]
      else [ ]
    ) (lib.attrsToList (builtins.readDir dir));

  resolveImport =
    x:
    if builtins.isList x then lib.concatMap resolveImport x
    else if builtins.isPath x then
      let s = toString x; in
      if lib.hasSuffix ".nix" s then
        if builtins.pathExists x then [ x ]
        else throw "[nixy] file not found: ${s}"
      else if builtins.pathExists x then scanDir x
      else throw "[nixy] path not found: ${s}"
    else if builtins.isFunction x || builtins.isAttrs x then [ x ]
    else throw "[nixy] unsupported import type: ${builtins.typeOf x}";

  loadModule =
    label: m:
    let
      loc = if builtins.isPath m then toString m else label;
      val = if builtins.isPath m then import m else m;
    in
    if builtins.isFunction val || builtins.isAttrs val then
      lib.setDefaultModuleLocation loc val
    else
      throw "[nixy] ${loc}: expected function or attrset, got ${builtins.typeOf val}";

  isOption = x: builtins.isAttrs x && (x._type or null) == "option";

  toOptions =
    path: attrs:
    lib.mapAttrs (
      name: value:
      let p = path ++ [ name ]; in
      if isOption value then value
      else if builtins.isAttrs value then
        lib.mkOption {
          type = lib.types.submodule { options = toOptions p value; };
          default = { };
        }
      else
        throw "[nixy] schema '${lib.concatStringsSep "." p}': expected option or attrset, got ${builtins.typeOf value}"
    ) attrs;

  deepMerge = lib.types.mkOptionType {
    name = "deepMerge";
    check = builtins.isAttrs;
    merge = _: defs: lib.foldl' lib.recursiveUpdate { } (map (d: d.value) defs);
  };

  buildNode =
    name: node: traits:
    let
      missing = builtins.filter (t: !traits ? ${t}) node.traits;
    in
    lib.throwIf (missing != [ ]) "[nixy] node '${name}': unknown traits — ${toString missing}" {
      inherit (node) schema traits;
      module = {
        _file = "<nixy/node:${name}>";
        imports =
          map (
            tName:
            builtins.addErrorContext "loading trait '${tName}'" (
              loadModule "trait:${tName}@${name}" traits.${tName}
            )
          ) node.traits
          ++ lib.imap0 (
            i: m:
            builtins.addErrorContext "loading include[${toString i}]" (
              loadModule "include:${toString i}@${name}" m
            )
          ) node.includes;
      };
    };

  mkCore =
    { config, ... }:
    {
      _file = "<nixy/core>";
      options = {
        schema = lib.mkOption { type = deepMerge; default = { }; };
        traits = lib.mkOption { type = lib.types.attrsOf lib.types.raw; default = { }; };
        nodes = lib.mkOption {
          type = lib.types.lazyAttrsOf (lib.types.submodule {
            options = {
              traits = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
              schema = lib.mkOption {
                type = lib.types.submodule { options = toOptions [ ] config.schema; };
                default = { };
              };
              includes = lib.mkOption { type = lib.types.listOf lib.types.raw; default = [ ]; };
            };
          });
          default = { };
        };
        output = lib.mkOption { type = deepMerge; default = { }; };
      };
    };

  evaluated = lib.evalModules {
    class = "nixy";
    modules =
      map (loadModule "<inline>") (lib.concatMap resolveImport (lib.toList imports))
      ++ [ mkCore ];
    specialArgs = args;
  };

  cfg = evaluated.config;

in
{
  nodes = lib.mapAttrs (
    name: node:
    builtins.addErrorContext "building node '${name}'" (
      buildNode name node cfg.traits
    )
  ) cfg.nodes;

  output = cfg.output;

  extend =
    extra:
    import ./eval.nix {
      inherit lib;
      imports = lib.toList imports ++ lib.toList (extra.imports or [ ]);
      args = args // (extra.args or { });
      exclude = if extra ? exclude then extra.exclude else exclude;
    };
}
