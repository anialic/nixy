{
  imports ? [ ],
  args ? { },
  exclude ? null,
}:

let

  isNix =
    s:
    let l = builtins.stringLength s; in
    l >= 4 && builtins.substring (l - 4) 4 s == ".nix";

  toList = x: if builtins.isList x then x else [ x ];

  defaultExclude =
    { name, ... }:
    let c = builtins.substring 0 1 name; in
    c == "_"
    || c == "."
    || name == "flake.nix"
    || name == "default.nix";

  mkExcludeFn =
    e:
    if e == null then defaultExclude
    else if builtins.isFunction e then e
    else throw "[nixy] 'exclude' must be a function";

  classifyEntry =
    path: name: kind:
    let
      k = if kind == "unknown" then builtins.readFileType path else kind;
    in
    if k == "regular" then
      if isNix name then "nix" else null
    else if k == "directory" then "directory"
    else if k == "symlink" then
      if builtins.pathExists (path + "/.") then "directory"
      else if isNix name && builtins.pathExists path then "nix"
      else null
    else null;

  scanDir =
    exFn: dir:
    let entries = builtins.readDir dir; in
    builtins.concatMap (
      name:
      let
        kind = entries.${name};
        path = dir + "/${name}";
        cls = classifyEntry path name kind;
      in
      if cls == null || exFn { inherit name path; } then [ ]
      else if cls == "directory" then scanDir exFn path
      else [ path ]
    ) (builtins.attrNames entries);

  resolveImports =
    exFn:
    let
      go =
        x:
        if builtins.isList x then builtins.concatMap go x
        else if builtins.isPath x then
          let
            s = toString x;
            t = builtins.addErrorContext "[nixy] while resolving '${s}'" (builtins.readFileType x);
            isDir = t == "directory"
              || (t == "symlink" && builtins.pathExists (x + "/."));
          in
          if isDir then scanDir exFn x
          else if isNix s then [ x ]
          else throw "[nixy] not a .nix file or directory: ${s}"
        else if builtins.isFunction x || builtins.isAttrs x then [ x ]
        else throw "[nixy] unsupported import type: ${builtins.typeOf x}";
    in
    go;

  loadMod =
    modArgs: m:
    let
      isP = builtins.isPath m;
      loc = if isP then toString m else "<inline>";
      raw = if isP then import m else m;
      val = builtins.addErrorContext "[nixy] while loading '${loc}'" (
        if builtins.isFunction raw then raw modArgs else raw
      );
    in
    if builtins.isAttrs val then val
    else throw "[nixy] '${loc}': expected attrset, got ${builtins.typeOf val}";

  mergeSchema =
    path: a: b:
    b // builtins.mapAttrs (
      name: va:
      if b ? ${name} then
        let
          vb = b.${name};
          p = if path == "" then name else "${path}.${name}";
        in
        if builtins.isAttrs va && builtins.isAttrs vb then mergeSchema p va vb
        else if builtins.isAttrs va || builtins.isAttrs vb then
          throw "[nixy] schema '${p}': conflict between subtree and leaf"
        else throw "[nixy] schema '${p}': declared twice"
      else va
    ) a;

  mergeValues =
    a: b:
    b // builtins.mapAttrs (
      name: va:
      if b ? ${name} then
        if builtins.isAttrs va && builtins.isAttrs b.${name} then mergeValues va b.${name}
        else b.${name}
      else va
    ) a;

  emptySt = { schema = { }; traits = { }; rawNodes = { }; };

  mergeMod =
    st: mod:
    let
      newTraits = mod.traits or { };
      newNodes = mod.nodes or { };
      dups = builtins.intersectAttrs st.rawNodes newNodes;
    in
    {
      schema = mergeSchema "" st.schema (mod.schema or { });
      traits = st.traits // builtins.mapAttrs (
        name: v:
        if st.traits ? ${name} then st.traits.${name} ++ [ v ] else [ v ]
      ) newTraits;
      rawNodes =
        if dups != { } then
          throw "[nixy] duplicate node '${builtins.head (builtins.attrNames dups)}'"
        else st.rawNodes // newNodes;
    };

  buildNode =
    globalSchema: globalTraits: name: node:
    let
      traitNames = node.traits or [ ];
      includes = node.includes or [ ];
      resolvedTraits =
        if traitNames == [ ] then [ ]
        else builtins.concatMap (
          t:
          if globalTraits ? ${t} then globalTraits.${t}
          else throw "[nixy] node '${name}': unknown trait '${t}'"
        ) traitNames;
    in
    {
      schema = if node ? schema then mergeValues globalSchema node.schema else globalSchema;
      traits = traitNames;
      module = {
        _file = "<nixy:${name}>";
        imports =
          if traitNames == [ ] then includes
          else if includes == [ ] then resolvedTraits
          else resolvedTraits ++ includes;
      };
    };

  evalWith =
    modArgs: exFn: resolved: st:
    let
      nodes = builtins.mapAttrs (
        name: node:
        builtins.addErrorContext "[nixy] while building node '${name}'" (
          buildNode st.schema st.traits name node
        )
      ) st.rawNodes;
    in
    {
      inherit (st) schema traits;
      inherit nodes;

      extend =
        extra:
        let
          newExFn = if extra ? exclude then mkExcludeFn extra.exclude else exFn;
          er = builtins.concatMap (resolveImports newExFn) (toList (extra.imports or [ ]));
          ar = resolved ++ er;
        in
        if extra ? args then
          init (modArgs // extra.args) newExFn ar
        else
          evalWith modArgs newExFn ar
            (builtins.foldl' (acc: m: mergeMod acc (loadMod modArgs m)) st er);
    };

  init =
    modArgs: exFn: resolved:
    evalWith modArgs exFn resolved
      (builtins.foldl' (st: m: mergeMod st (loadMod modArgs m)) emptySt resolved);

  exFn = mkExcludeFn exclude;
  resolved = builtins.concatMap (resolveImports exFn) (toList imports);

in
init args exFn resolved
