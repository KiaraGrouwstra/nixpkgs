{
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (types) port str;
in
{
  meta = {
    description = ''
      Contract for SMTP email sending where a consumer requests
      mail relay configuration and a provider supplies the connection details.
    '';
    maintainers = with lib.maintainers; [
      ibizaman
    ];
  };
  interface = {
    request = {
      sender = mkOption {
        description = ''
          Email address used as the sender (From header).
        '';
        type = str;
        example = "noreply@example.com";
      };
    };
    result = {
      host = mkOption {
        description = ''
          Hostname of the SMTP server.
        '';
        type = str;
      };

      port = mkOption {
        description = ''
          Port of the SMTP server.
        '';
        type = port;
      };

      username = mkOption {
        description = ''
          Username for SMTP authentication.
        '';
        type = str;
      };

      passwordFile = mkOption {
        description = ''
          Path to a file containing the SMTP password.
        '';
        type = str;
      };
    };
  };
  behaviorTest =
    {
      name,
      providerRoot,
      extraModules ? [ ],
    }:
    {
      name = "contracts_smtp_${name}";
      containers.machine =
        { config, pkgs, ... }:
        {
          imports = extraModules;

          options.test = {
            sender = mkOption {
              type = str;
              default = "test@test.local";
            };
          };

          config = lib.mkMerge [
            (lib.setAttrByPath providerRoot {
              request = {
                inherit (config.test) sender;
              };
            })
            { environment.systemPackages = [ pkgs.netcat-openbsd ]; }
          ];
        };

      testScript =
        { containers, ... }:
        let
          inherit (lib.getAttrFromPath providerRoot containers.machine) result;
        in
        ''
          with subtest("Password file exists"):
              machine.succeed("test -f ${result.passwordFile}")

          with subtest("SMTP server accepts connection"):
              machine.wait_for_open_port(${toString result.port})
              banner = machine.succeed(
                  "echo QUIT | nc -w5 ${result.host} ${toString result.port}"
              ).strip()
              print(f"SMTP banner: {banner}")
              assert banner.startswith("220"), f"unexpected SMTP banner: {banner}"
        '';
    };
}
