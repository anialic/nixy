{
  lib,
  imports ? [ ],
  args ? { },
  exclude ? null,
}:

let
  defaultExclude =
    { name, ... }:
    lib.hasPrefix "_" name || lib.hasPrefix "." name || name == "flake.nix" || name == "default.nix";

  mkExcludeFn =
    e:
    if e == null then defaultExclude
    else if builtins.isFunction e then e
    else throw "[nixy] 'exclude' must be a function";

  classifyEntry =
    dir: name: kind:
    if kind == "directory" then "directory"
    else if kind == "regular" then
      if lib.hasSuffix ".nix" name then "nix" else null
    else if kind == "symlink" then
      let target = dir + "/${name}"; in
      if builtins.pathExists (target + "/.") then "directory"
      else if lib.hasSuffix ".nix" name && builtins.pathExists target then "nix"
      else null
    else null;

  mkScanDir =
    excludeFn: dir:
    lib.concatMap (
      { name, value }:
      let
        path = lib.path.append dir name;
        cls  = classifyEntry dir name value;
      in
      if cls == null || excludeFn { inherit name path; } then [ ]
      else if cls == "directory" then mkScanDir excludeFn path
      else [ path ]
    ) (lib.attrsToList (builtins.readDir dir));

  mkResolveImport =
    excludeFn:
    let
      scanDir = mkScanDir excludeFn;
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
    in
    resolveImport;

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

  warnDeepMerge = lib.types.mkOptionType {
    name = "warnDeepMerge";
    check = builtins.isAttrs;
    merge =
      loc: defs:
      let
        keys = lib.concatMap (d: builtins.attrNames d.value) defs;
      in
      lib.warn
        "[nixy] undeclared schema keys: ${lib.concatStringsSep ", " keys} (at '${lib.showOption loc}')"
        (lib.foldl' lib.recursiveUpdate { } (map (d: d.value) defs));
  };

  buildNode =
    name: node: globalTraits:
    let
      traitNames = lib.lists.unique node.traits;
      missing = builtins.filter (t: !globalTraits ? ${t}) traitNames;
    in
    lib.throwIf (missing != [ ]) "[nixy] node '${name}': unknown traits — ${toString missing}" {
      inherit (node) schema;
      traits = traitNames;
      module = {
        _file = "<nixy/node:${name}>";
        imports =
          map (
            tName:
            builtins.addErrorContext "loading trait '${tName}'" (
              loadModule "trait:${tName}@${name}" globalTraits.${tName}
            )
          ) traitNames
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
        traits = lib.mkOption {
          type = lib.types.attrsWith {
            elemType = lib.types.deferredModule;
            placeholder = "traitName";
          };
          default = { };
        };
        nodes = lib.mkOption {
          type = lib.types.attrsWith {
            elemType = lib.types.submodule {
              options = {
                traits = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
                schema = lib.mkOption {
                  type = lib.types.submodule {
                    freeformType = warnDeepMerge;
                    options = toOptions [ ] config.schema;
                  };
                  default = { };
                };
                includes = lib.mkOption { type = lib.types.listOf lib.types.raw; default = [ ]; };
              };
            };
            lazy = true;
            placeholder = "nodeName";
          };
          default = { };
          apply = nodes:
            lib.mapAttrs (
              name: node:
              builtins.addErrorContext "building node '${name}'" (
                buildNode name node config.traits
              )
            ) nodes;
        };
        output = lib.mkOption { type = deepMerge; default = { }; };
      };
    };

  buildResult =
    ev: currentArgs: currentExcludeFn:
    {
      nodes   = ev.config.nodes;
      output  = ev.config.output;
      schema  = ev.config.schema;
      traits  = ev.config.traits;
      options = ev.options;

      extend =
        extra:
        let
          extraArgs    = extra.args or { };
          newArgs      = lib.recursiveUpdate currentArgs extraArgs;
          newExcludeFn = if extra ? exclude then mkExcludeFn extra.exclude else currentExcludeFn;
          newResolve   = mkResolveImport newExcludeFn;
          newModules   = lib.concatMap newResolve (lib.toList (extra.imports or [ ]));
        in
        buildResult
          (ev.extendModules {
            modules = newModules;
            specialArgs = extraArgs;
          })
          newArgs
          newExcludeFn;
    };

  excludeFn     = mkExcludeFn exclude;
  resolveImport = mkResolveImport excludeFn;

  ev = lib.evalModules {
    class = "nixy";
    modules =
      map (loadModule "<inline>") (lib.concatMap resolveImport (lib.toList imports))
      ++ [ mkCore ];
    specialArgs = args;
  };

in
buildResult ev args excludeFn
