{
  schema.ssh = {
    port = 22;
    permitRoot = false;
  };

  traits.ssh =
    { schema, ... }:
    {
      services.openssh = {
        enable = true;
        ports = [ schema.ssh.port ];
        settings.PermitRootLogin = if schema.ssh.permitRoot then "yes" else "no";
      };
    };
}
