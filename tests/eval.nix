let
  eval = import ../nix/eval.nix;

  assertEq =
    name: actual: expected:
    if actual == expected then true
    else throw "FAIL: ${name}\n  expected: ${builtins.toJSON expected}\n  actual:   ${builtins.toJSON actual}";

  assertThrows =
    name: expr:
    let
      result = builtins.tryEval (builtins.deepSeq expr expr);
    in
    if !result.success then true
    else throw "FAIL: ${name} — expected error, got success";

  test-basic =
    let
      r = eval {
        imports = [
          {
            schema.ssh.port = 22;
            traits.ssh = { schema, ... }: {
              services.openssh.ports = [ schema.ssh.port ];
            };
            nodes.server = {
              traits = [ "ssh" ];
              schema.ssh.port = 2222;
            };
          }
        ];
      };
    in
    assertEq "basic: node schema override" r.nodes.server.schema.ssh.port 2222
    && assertEq "basic: node traits" r.nodes.server.traits [ "ssh" ]
    && assertEq "basic: global schema" r.schema.ssh.port 22;

  test-defaults =
    let
      r = eval {
        imports = [
          {
            schema.base = { hostName = "nixos"; user = "alice"; };
            nodes.box = { };
          }
        ];
      };
    in
    assertEq "defaults: hostName" r.nodes.box.schema.base.hostName "nixos"
    && assertEq "defaults: user" r.nodes.box.schema.base.user "alice";

  test-schema-conflict =
    assertThrows "schema-conflict" (
      eval {
        imports = [
          { schema.ssh.port = 22; }
          { schema.ssh.port = 80; }
        ];
      }
    ).schema;

  test-schema-subtree-leaf =
    assertThrows "schema-subtree-leaf" (
      eval {
        imports = [
          { schema.ssh = { port = 22; }; }
          { schema.ssh = 42; }
        ];
      }
    ).schema;

  test-schema-merge =
    let
      r = eval {
        imports = [
          { schema.ssh.port = 22; }
          { schema.ssh.user = "root"; }
          { schema.base.hostName = "box"; }
        ];
      };
    in
    assertEq "schema-merge: port" r.schema.ssh.port 22
    && assertEq "schema-merge: user" r.schema.ssh.user "root"
    && assertEq "schema-merge: hostName" r.schema.base.hostName "box";

  test-unknown-trait =
    assertThrows "unknown-trait" (
      eval {
        imports = [
          {
            nodes.server = { traits = [ "nonexistent" ]; };
          }
        ];
      }
    ).nodes.server.module;

  test-duplicate-node =
    assertThrows "duplicate-node" (
      eval {
        imports = [
          { nodes.server = { }; }
          { nodes.server = { }; }
        ];
      }
    ).nodes;

  test-trait-merge =
    let
      r = eval {
        imports = [
          {
            traits.ssh = { services.openssh.enable = true; };
          }
          {
            traits.ssh = { services.openssh.settings.PasswordAuthentication = false; };
          }
          {
            nodes.server = { traits = [ "ssh" ]; };
          }
        ];
      };
    in
    assertEq "trait-merge: two imports" (builtins.length r.nodes.server.module.imports) 2;

  test-includes =
    let
      r = eval {
        imports = [
          {
            traits.base = { };
            nodes.server = {
              traits = [ "base" ];
              includes = [
                { services.nginx.enable = true; }
                { services.fail2ban.enable = true; }
              ];
            };
          }
        ];
      };
    in
    assertEq "includes: total imports" (builtins.length r.nodes.server.module.imports) 3;

  test-extra-schema-keys =
    let
      r = eval {
        imports = [
          {
            schema.base.hostName = "nixos";
            nodes.server = {
              schema.base.hostName = "srv";
              schema.extra.foo = "bar";
            };
          }
        ];
      };
    in
    assertEq "extra-keys: hostName override" r.nodes.server.schema.base.hostName "srv"
    && assertEq "extra-keys: extra.foo" r.nodes.server.schema.extra.foo "bar";

  test-inline-function =
    let
      r = eval {
        imports = [
          (
            { myArg, ... }:
            {
              schema.test.value = myArg;
            }
          )
        ];
        args = { myArg = 42; };
      };
    in
    assertEq "inline-function: value" r.schema.test.value 42;

  test-extend =
    let
      base = eval {
        imports = [
          {
            schema.ssh.port = 22;
            traits.ssh = { };
            nodes.server = { traits = [ "ssh" ]; };
          }
        ];
      };
      extended = base.extend {
        imports = [
          {
            schema.base.hostName = "ext";
            traits.monitoring = { };
            nodes.monitor = { traits = [ "monitoring" ]; };
          }
        ];
      };
    in
    assertEq "extend: original node exists" (extended.nodes ? server) true
    && assertEq "extend: new node exists" (extended.nodes ? monitor) true
    && assertEq "extend: original schema preserved" extended.schema.ssh.port 22
    && assertEq "extend: new schema added" extended.schema.base.hostName "ext";

  test-extend-args =
    let
      base = eval {
        imports = [
          ({ a, ... }: { schema.vals.a = a; })
        ];
        args = { a = 1; };
      };
      extended = base.extend {
        imports = [
          ({ b, ... }: { schema.vals.b = b; })
        ];
        args = { b = 2; };
      };
    in
    assertEq "extend-args: a" extended.schema.vals.a 1
    && assertEq "extend-args: b" extended.schema.vals.b 2;

  test-empty-schema =
    let
      r = eval {
        imports = [
          {
            schema.opts = { };
            nodes.server = {
              schema.opts.custom = "value";
            };
          }
        ];
      };
    in
    assertEq "empty-schema: custom key" r.nodes.server.schema.opts.custom "value";

  test-deep-merge =
    let
      r = eval {
        imports = [
          {
            schema.net = {
              dns = [ "1.1.1.1" ];
              iface = "eth0";
              opts = { mtu = 1500; tso = true; };
            };
            nodes.server = {
              schema.net.dns = [ "8.8.8.8" ];
              schema.net.opts.mtu = 9000;
            };
          }
        ];
      };
    in
    assertEq "deep-merge: replaced leaf" r.nodes.server.schema.net.dns [ "8.8.8.8" ]
    && assertEq "deep-merge: untouched leaf" r.nodes.server.schema.net.iface "eth0"
    && assertEq "deep-merge: nested override" r.nodes.server.schema.net.opts.mtu 9000
    && assertEq "deep-merge: nested untouched" r.nodes.server.schema.net.opts.tso true;

  test-multi-node =
    let
      r = eval {
        imports = [
          {
            schema.base.hostName = "default";
            traits.base = { };
            nodes.web = { traits = [ "base" ]; schema.base.hostName = "web"; };
            nodes.db = { traits = [ "base" ]; schema.base.hostName = "db"; };
          }
        ];
      };
    in
    assertEq "multi-node: web" r.nodes.web.schema.base.hostName "web"
    && assertEq "multi-node: db" r.nodes.db.schema.base.hostName "db";

  test-trait-attrset =
    let
      r = eval {
        imports = [
          {
            traits.simple = { boot.loader.grub.enable = true; };
            nodes.server = { traits = [ "simple" ]; };
          }
        ];
      };
    in
    assertEq "trait-attrset: module exists" (builtins.length r.nodes.server.module.imports) 1;

  test-exclude =
    let
      r = eval {
        imports = [
          { schema.a = 1; }
        ];
        exclude = { name, ... }: name == "should-not-matter.nix";
      };
    in
    assertEq "exclude: schema" r.schema.a 1;

  test-null-schema =
    let
      r = eval {
        imports = [
          {
            schema.base = { hostName = "nixos"; domain = null; };
            nodes.server = {
              schema.base.domain = "example.com";
            };
            nodes.local = { };
          }
        ];
      };
    in
    assertEq "null-schema: default null" r.nodes.local.schema.base.domain null
    && assertEq "null-schema: override" r.nodes.server.schema.base.domain "example.com";

  test-node-replaces-subtree =
    let
      r = eval {
        imports = [
          {
            schema.net = { dns = [ "1.1.1.1" ]; iface = "eth0"; };
            nodes.server = {
              schema.net = "disabled";
            };
          }
        ];
      };
    in
    assertEq "node-replaces-subtree" r.nodes.server.schema.net "disabled";

  test-empty-eval =
    let
      r = eval { };
    in
    assertEq "empty-eval: no nodes" r.nodes { }
    && assertEq "empty-eval: no schema" r.schema { };

  all =
    test-basic
    && test-defaults
    && test-schema-conflict
    && test-schema-subtree-leaf
    && test-schema-merge
    && test-unknown-trait
    && test-duplicate-node
    && test-trait-merge
    && test-includes
    && test-extra-schema-keys
    && test-inline-function
    && test-extend
    && test-extend-args
    && test-empty-schema
    && test-deep-merge
    && test-multi-node
    && test-trait-attrset
    && test-exclude
    && test-null-schema
    && test-node-replaces-subtree
    && test-empty-eval;

in
if all then "all ${toString 21} tests passed" else throw "unreachable"
