{ lib }:
rec {
  # Base option builder
  mkOpt =
    type: default:
    if default == null then
      lib.mkOption {
        type = lib.types.nullOr type;
        default = null;
      }
    else
      lib.mkOption { inherit type default; };

  # Expanded helpers
  helpers = {
    mkStr = mkOpt lib.types.str;
    mkBool = mkOpt lib.types.bool;
    mkInt = mkOpt lib.types.int;
    mkPort = mkOpt lib.types.port;
    mkPath = mkOpt lib.types.path;
    mkLines = mkOpt lib.types.lines;
    mkAttrs = mkOpt lib.types.attrs;

    mkList = elemType: mkOpt (lib.types.listOf elemType);
    mkListOf =
      type:
      lib.mkOption {
        type = lib.types.listOf type;
        default = [ ];
      };
    mkAttrsOf =
      type:
      lib.mkOption {
        type = lib.types.attrsOf type;
        default = { };
      };
    mkStrList = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    mkEnum = values: mkOpt (lib.types.enum values);
    mkEither = t1: t2: mkOpt (lib.types.either t1 t2);
    mkOneOf = types: mkOpt (lib.types.oneOf types);

    mkPackage = lib.mkOption { type = lib.types.package; };
    mkPackageOr =
      default:
      lib.mkOption {
        type = lib.types.package;
        inherit default;
      };
    mkRaw = lib.mkOption { type = lib.types.raw; };
    mkRawOr =
      default:
      lib.mkOption {
        type = lib.types.raw;
        inherit default;
      };
    mkNullable =
      type:
      lib.mkOption {
        type = lib.types.nullOr type;
        default = null;
      };

    mkSub =
      opts:
      lib.mkOption {
        type = lib.types.submodule { options = opts; };
        default = { };
      };
    mkSubList =
      opts:
      lib.mkOption {
        type = lib.types.listOf (lib.types.submodule { options = opts; });
        default = [ ];
      };

    mkEnable = lib.mkEnableOption;
  };

  defaultExclude =
    { name, ... }:
    let
      c = builtins.substring 0 1 name;
    in
    c == "_" || c == "." || name == "flake.nix" || name == "default.nix";

  scan =
    excludeFn: dir:
    lib.concatLists (
      lib.mapAttrsToList (
        name: type:
        let
          path = dir + "/${name}";
        in
        if excludeFn { inherit name path; } then
          [ ]
        else if type == "directory" then
          scan excludeFn path
        else if type == "regular" && lib.hasSuffix ".nix" name then
          [ path ]
        else
          [ ]
      ) (builtins.readDir dir)
    );

  resolveImport =
    excludeFn: x:
    if builtins.isPath x then
      if lib.hasSuffix ".nix" (toString x) then
        [ x ]
      else if builtins.pathExists x then
        scan excludeFn x
      else
        [ ]
    else if builtins.isString x then
      if builtins.substring 0 1 x == "/" then resolveImport excludeFn (/. + x) else [ ]
    else if builtins.isAttrs x then
      [ x ]
    else if builtins.isList x then
      lib.concatMap (resolveImport excludeFn) x
    else
      throw "nixy: invalid import type ${builtins.typeOf x}";

  deepMerge = lib.mkOptionType {
    name = "deepMerge";
    check = builtins.isAttrs;
    merge = _: defs: lib.foldl' lib.recursiveUpdate { } (map (d: d.value) defs);
  };

  deferredModules = lib.mkOptionType {
    name = "deferredModules";
    check = x: builtins.isList x || builtins.isFunction x || builtins.isAttrs x;
    merge =
      loc: defs:
      lib.concatMap (
        d: map (lib.setDefaultModuleLocation "${d.file}, via ${lib.showOption loc}") (lib.toList d.value)
      ) defs;
  };

  loadModule =
    x: if builtins.isPath x then lib.setDefaultModuleLocation (toString x) (import x) else x;

  mkCoreModule =
    {
      nixpkgs,
      inputs,
      args,
    }:
    { config, ... }:
    let
      moduleEntries = lib.mapAttrsToList (
        name: spec:
        lib.throwIf (spec.options ? enable) "nixy: module '${name}' cannot define 'enable'" {
          inherit name;
          inherit (spec)
            target
            requires
            options
            module
            ;
        }
      ) config.modules;

      mkConditionalType =
        modName: modOptions:
        let
          enableOnly = lib.types.submodule { options.enable = lib.mkEnableOption modName; };
          fullType = lib.types.submodule {
            options = {
              enable = lib.mkEnableOption modName;
            }
            // modOptions;
          };
        in
        lib.mkOptionType {
          name = "conditionalModule(${modName})";
          check = builtins.isAttrs;
          merge =
            loc: defs:
            let
              merged = lib.foldl' lib.recursiveUpdate { } (map (d: d.value) defs);
              enabled = merged.enable or false;
              extraKeys = builtins.filter (k: k != "enable") (builtins.attrNames merged);
            in
            if enabled == false && extraKeys != [ ] then
              throw "nixy: ${lib.concatStringsSep "." loc}: options set but enable = false (keys: ${lib.concatStringsSep ", " extraKeys})"
            else if enabled == true then
              fullType.merge loc defs
            else
              enableOnly.merge loc defs;
          getSubOptions = fullType.getSubOptions;
          getSubModules = fullType.getSubModules;
          substSubModules = _: mkConditionalType modName modOptions;
        };

      nodeOptions = lib.listToAttrs (
        map (
          m:
          lib.nameValuePair m.name (
            lib.mkOption {
              type = mkConditionalType m.name m.options;
              default = { };
            }
          )
        ) moduleEntries
      );

      nodeType = lib.types.submodule {
        options = {
          system = lib.mkOption { type = lib.types.str; };
          target = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          extraModules = lib.mkOption {
            type = lib.types.listOf lib.types.deferredModule;
            default = [ ];
          };
          instantiate = lib.mkOption {
            type = lib.types.nullOr lib.types.raw;
            default = null;
          };
        }
        // nodeOptions;
      };

      inferTarget = system: if lib.hasSuffix "-darwin" system then "darwin" else "nixos";

      enrichNode =
        name: node:
        let
          target = if node.target != null then node.target else inferTarget node.system;
        in
        {
          inherit name target;
          inherit (node) system;
          raw = node;
          clean =
            removeAttrs node [
              "system"
              "target"
              "extraModules"
              "instantiate"
            ]
            // {
              _name = name;
              _system = node.system;
              _target = target;
            };
        };

      enrichedNodes = lib.mapAttrs enrichNode config.nodes;
      allNodes = lib.mapAttrs (_: n: n.clean) enrichedNodes;

      buildNode =
        name:
        let
          enriched = enrichedNodes.${name};
          checked = map (
            m:
            let
              modConfig = enriched.raw.${m.name} or { };
              enabled = modConfig.enable or false;
              targetMatch = m.target == null || m.target == enriched.target;
              missingDeps = lib.filter (
                dep:
                let
                  depConfig = enriched.raw.${dep} or { };
                in
                !(depConfig.enable or false)
              ) m.requires;
            in
            {
              inherit
                m
                enabled
                targetMatch
                missingDeps
                ;
              error =
                if enabled == true && !targetMatch then
                  "${m.name}: requires target '${m.target}', got '${enriched.target}'"
                else if enabled == true && missingDeps != [ ] then
                  "${m.name}: requires ${lib.concatStringsSep ", " missingDeps}"
                else
                  null;
            }
          ) moduleEntries;
          errors = builtins.filter (e: e != null) (map (c: c.error) checked);
          activeModules = builtins.filter (
            c: c.enabled == true && c.targetMatch && c.m.module != [ ]
          ) checked;
          instantiate =
            if enriched.raw.instantiate != null then
              enriched.raw.instantiate
            else
              let
                targetDef = config.targets.${enriched.target} or null;
              in
              if targetDef != null then
                targetDef.instantiate
              else
                throw "nixy: node '${name}' has undefined target '${enriched.target}'";
        in
        lib.throwIf (errors != [ ])
          (
            "nixy: configuration errors in node '${name}':\n"
            + lib.concatMapStringsSep "\n" (e: "  • ${e}") errors
          )
          (instantiate {
            system = enriched.system;
            specialArgs = {
              inherit name inputs;
              system = enriched.system;
              node = enriched.clean;
              nodes = allNodes;
            }
            // args;
            modules = lib.concatMap (c: lib.toList c.m.module) activeModules ++ enriched.raw.extraModules;
          });

      nodesByTarget = builtins.groupBy (n: enrichedNodes.${n}.target) (builtins.attrNames enrichedNodes);

      targetOutputs = lib.mapAttrs' (
        target: def: lib.nameValuePair def.output (lib.genAttrs (nodesByTarget.${target} or [ ]) buildNode)
      ) config.targets;

      perSystemOutputs = lib.genAttrs config.systems (
        system:
        config.perSystem {
          inherit system;
          pkgs = nixpkgs.legacyPackages.${system};
        }
      );

      mkPerSystemOutput =
        output:
        lib.filterAttrs (_: v: v != { }) (
          lib.genAttrs config.systems (system: perSystemOutputs.${system}.${output} or { })
        );

      formatter = lib.genAttrs config.systems (
        system:
        let
          ps = perSystemOutputs.${system};
        in
        if ps ? formatter && ps.formatter != null then
          ps.formatter
        else
          nixpkgs.legacyPackages.${system}.nixfmt-rfc-style
      );

      # Collect option paths from a module's options
      collectPaths =
        prefix: opts:
        lib.concatLists (
          lib.mapAttrsToList (
            name: opt:
            let
              path = if prefix == "" then name else "${prefix}.${name}";
            in
            if opt ? _type && opt._type == "option" then
              [
                {
                  inherit path;
                  type = opt.type.description or opt.type.name or "?";
                  default = opt.default or null;
                  hasDefault = opt ? default;
                }
              ]
            else if builtins.isAttrs opt then
              collectPaths path opt
            else
              [ ]
          ) opts
        );

      optionsDoc =
        let
          moduleCount = builtins.length moduleEntries;
          totalOptions = lib.foldl' (
            acc: m: acc + builtins.length (collectPaths "" m.options)
          ) 0 moduleEntries;

          formatModule =
            m:
            let
              paths = collectPaths "" m.options;
              optCount = builtins.length paths;
              targetBadge = if m.target != null then " [${m.target}]" else "";
              requiresBadge = if m.requires != [ ] then " <- ${lib.concatStringsSep ", " m.requires}" else "";
              summary = "${m.name}${targetBadge}${requiresBadge} (${toString optCount} options)";
              body =
                if paths == [ ] then
                  "_No options_"
                else
                  ''
                    | Option | Type | Default |
                    |--------|------|---------|
                    ${lib.concatMapStringsSep "\n" (
                      p:
                      let
                        defStr = if p.default == null then "-" else "`${builtins.toJSON p.default}`";
                      in
                      "| `${p.path}` | ${p.type} | ${defStr} |"
                    ) paths}'';
            in
            ''
              <details>
              <summary>${summary}</summary>

              ${body}

              </details>'';
        in
        ''
          # nixy modules

          > ${toString moduleCount} modules, ${toString totalOptions} options

          ${lib.concatMapStringsSep "\n\n" formatModule moduleEntries}
        '';

      nodesDoc =
        let
          nodeCount = builtins.length (builtins.attrNames enrichedNodes);
          byTarget = lib.groupBy (n: enrichedNodes.${n}.target) (builtins.attrNames enrichedNodes);

          formatNode =
            name:
            let
              e = enrichedNodes.${name};
              enabledMods = lib.filter (m: (e.raw.${m.name} or { }).enable or false) moduleEntries;
              modCount = builtins.length enabledMods;
              summary = "${name} [${e.system}] (${toString modCount} modules)";
              body =
                if enabledMods == [ ] then
                  "_No modules enabled_"
                else
                  lib.concatMapStringsSep "\n" (m: "- ${m.name}") enabledMods;
            in
            ''
              <details>
              <summary>${summary}</summary>

              ${body}

              </details>'';

          formatTarget = target: nodes: ''
            ### ${target}

            ${lib.concatMapStringsSep "\n\n" formatNode nodes}
          '';
        in
        ''
          # nixy nodes

          > ${toString nodeCount} nodes

          ${lib.concatStringsSep "\n\n" (lib.mapAttrsToList formatTarget byTarget)}
        '';

      dependencyGraph =
        let
          depLines = lib.concatLists (map (m: map (dep: "  ${dep} --> ${m.name}") m.requires) moduleEntries);
          moduleDeps = lib.concatStringsSep "\n" depLines;

          # Node -> modules relationships
          nodeLines = lib.concatLists (
            map (
              name:
              let
                e = enrichedNodes.${name};
                enabledMods = lib.filter (m: (e.raw.${m.name} or { }).enable or false) moduleEntries;
              in
              map (m: "  ${name}([${name}]) -.-> ${m.name}") enabledMods
            ) (builtins.attrNames enrichedNodes)
          );
          nodeModules = lib.concatStringsSep "\n" nodeLines;

          # Module styling by target
          moduleStyles = lib.concatMapStringsSep "\n" (
            m:
            let
              style =
                if m.target == "nixos" then
                  ":::nixos"
                else if m.target == "darwin" then
                  ":::darwin"
                else if m.target == "home" then
                  ":::home"
                else
                  "";
            in
            "  ${m.name}[${m.name}]${style}"
          ) moduleEntries;

          depsSection =
            if depLines == [ ] then
              ""
            else
              ''

                  %% Dependencies
                ${moduleDeps}'';
        in
        ''
          # nixy dependency graph

          ```mermaid
          flowchart LR
            %% Modules
          ${moduleStyles}${depsSection}

            %% Nodes
          ${nodeModules}

            %% Styles
            classDef nixos fill:#4c566a,stroke:#88c0d0,color:#eceff4
            classDef darwin fill:#4c566a,stroke:#a3be8c,color:#eceff4
            classDef home fill:#4c566a,stroke:#ebcb8b,color:#eceff4
            classDef default fill:#3b4252,stroke:#81a1c1,color:#eceff4
          ```
        '';

      # Options check with clear formatting
      optionsCheck =
        let
          collectMissing =
            prefix: opts:
            lib.concatLists (
              lib.mapAttrsToList (
                name: opt:
                let
                  path = if prefix == "" then name else "${prefix}.${name}";
                in
                if opt ? _type && opt._type == "option" then
                  if opt ? default then [ ] else [ path ]
                else if builtins.isAttrs opt then
                  collectMissing path opt
                else
                  [ ]
              ) opts
            );

          modulesWithMissing = lib.filter (m: m.missing != [ ]) (
            map (m: {
              inherit (m) name target;
              missing = collectMissing "" m.options;
            }) moduleEntries
          );

          totalMissing = lib.foldl' (acc: m: acc + builtins.length m.missing) 0 modulesWithMissing;
        in
        if modulesWithMissing == [ ] then
          ''

            All options have default values.
          ''
        else
          ''
            # Options Missing Defaults

            > ${toString totalMissing} options without defaults in ${toString (builtins.length modulesWithMissing)} modules

            ${lib.concatMapStringsSep "\n\n" (
              m:
              let
                targetStr = if m.target != null then " [${m.target}]" else "";
              in
              ''
                <details>
                <summary>${m.name}${targetStr} (${toString (builtins.length m.missing)} missing)</summary>

                ${lib.concatMapStringsSep "\n" (p: "- `${p}`") m.missing}

                </details>''
            ) modulesWithMissing}
          '';

      optionsCheckFailed = lib.hasPrefix "# Options Missing" optionsCheck;

      mkApp = system: name: script: {
        type = "app";
        program = toString (nixpkgs.legacyPackages.${system}.writeShellScript "nixy-${name}" script);
      };

      builtinApps = lib.genAttrs config.systems (system: {
        allOptions = mkApp system "options" ''
          cat <<'EOF'
          ${optionsDoc}
          EOF
        '';
        allNodes = mkApp system "nodes" ''
          cat <<'EOF'
          ${nodesDoc}
          EOF
        '';
        checkOptions = mkApp system "check" ''
          cat <<'EOF'
          ${optionsCheck}
          EOF
          ${lib.optionalString optionsCheckFailed "exit 1"}
        '';
        graph = mkApp system "graph" ''
          cat <<'EOF'
          ${dependencyGraph}
          EOF
        '';
      });

      rulesErrors = map (r: r.message) (builtins.filter (r: r.assertion == false) config.rules);

      checkRules = lib.throwIf (rulesErrors != [ ]) (
        "nixy: rules failed:\n" + lib.concatMapStringsSep "\n" (e: "  • ${e}") rulesErrors
      ) true;

      targetOutputsChecked = lib.mapAttrs (
        _: configs:
        lib.mapAttrs (
          _: cfg:
          assert checkRules;
          cfg
        ) configs
      ) targetOutputs;
    in
    {
      _file = "<nixy/core>";

      options = {
        systems = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "x86_64-linux"
            "aarch64-linux"
            "aarch64-darwin"
            "x86_64-darwin"
          ];
        };

        modules = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                target = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                };
                requires = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                };
                options = lib.mkOption {
                  type = deepMerge;
                  default = { };
                };
                module = lib.mkOption {
                  type = deferredModules;
                  default = [ ];
                };
              };
            }
          );
          default = { };
        };

        targets = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                instantiate = lib.mkOption { type = lib.types.raw; };
                output = lib.mkOption { type = lib.types.str; };
              };
            }
          );
          default = { };
        };

        nodes = lib.mkOption {
          type = lib.types.attrsOf nodeType;
          default = { };
        };

        rules = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                assertion = lib.mkOption { type = lib.types.bool; };
                message = lib.mkOption { type = lib.types.str; };
              };
            }
          );
          default = [ ];
        };

        perSystem = lib.mkOption {
          type = lib.types.functionTo (lib.types.lazyAttrsOf lib.types.raw);
          default = _: { };
        };

        flake = lib.mkOption {
          type = lib.types.submoduleWith {
            modules = [ { freeformType = lib.types.lazyAttrsOf lib.types.raw; } ];
          };
          default = { };
        };
      };

      config = {
        targets.nixos = {
          instantiate =
            {
              system,
              modules,
              specialArgs,
            }:
            if lib ? nixosSystem then
              lib.nixosSystem { inherit system modules specialArgs; }
            else
              import (nixpkgs.legacyPackages.${system}.path + "/nixos/lib/eval-config.nix") {
                inherit system modules specialArgs;
              };
          output = "nixosConfigurations";
        };
        flake =
          lib.mapAttrs (_: lib.mkDefault) targetOutputsChecked
          // {
            formatter = lib.mkDefault formatter;
          }
          // {
            apps = lib.mkDefault (
              lib.genAttrs config.systems (sys: (perSystemOutputs.${sys}.apps or { }) // builtinApps.${sys})
            );
          }
          // lib.genAttrs [ "packages" "devShells" "checks" "legacyPackages" ] (
            o: lib.mkDefault (mkPerSystemOutput o)
          );
      };
    };

  eval =
    {
      nixpkgs,
      inputs,
      imports,
      args,
      exclude,
    }:
    let
      excludeFn = if exclude != null then exclude else defaultExclude;
      allModules = lib.concatMap (resolveImport excludeFn) (lib.toList imports);
      coreModule = mkCoreModule { inherit nixpkgs inputs args; };
      evaluated = lib.evalModules {
        class = "nixy";
        modules = map loadModule allModules ++ [ coreModule ];
        specialArgs = {
          inherit lib nixpkgs inputs;
          pkgsFor = system: nixpkgs.legacyPackages.${system};
        }
        // helpers
        // args;
      };
    in
    lib.filterAttrs (_: v: v != { }) evaluated.config.flake;
}
