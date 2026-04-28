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
      Contract for LDAP integration where a consumer requests
      access to a directory group and a provider supplies connection details.
    '';
    maintainers = with lib.maintainers; [
      ibizaman
    ];
  };
  interface = {
    request = {
      group = mkOption {
        description = ''
          LDAP group that the service requires.
          The provider is expected to create this group.
        '';
        type = str;
        example = "myapp-users";
      };
    };
    result = {
      host = mkOption {
        description = ''
          Hostname of the LDAP server.
        '';
        type = str;
      };

      port = mkOption {
        description = ''
          Port of the LDAP server.
        '';
        type = port;
      };

      baseDN = mkOption {
        description = ''
          Base distinguished name for LDAP queries.
        '';
        type = str;
        example = "dc=example,dc=com";
      };

      userBaseDN = mkOption {
        description = ''
          Base DN under which user entries reside.
        '';
        type = str;
        example = "ou=people,dc=example,dc=com";
      };

      groupBaseDN = mkOption {
        description = ''
          Base DN under which group entries reside.
        '';
        type = str;
        example = "ou=groups,dc=example,dc=com";
      };

      bindDN = mkOption {
        description = ''
          DN used to bind (authenticate) to the LDAP server.
        '';
        type = str;
      };

      bindPasswordFile = mkOption {
        description = ''
          Path to a file containing the bind password.
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
      name = "contracts_ldap_${name}";
      containers.machine =
        { config, pkgs, ... }:
        {
          imports = extraModules;

          options.test = {
            group = mkOption {
              type = str;
              default = "testgroup";
            };
          };

          config = lib.mkMerge [
            (lib.setAttrByPath providerRoot {
              request = {
                inherit (config.test) group;
              };
            })
            {
              environment.systemPackages = [ pkgs.openldap ];
            }
          ];
        };

      testScript =
        { containers, ... }:
        let
          inherit (lib.getAttrFromPath providerRoot containers.machine) result;
        in
        ''
          with subtest("Password file exists"):
              machine.succeed("test -f ${result.bindPasswordFile}")

          with subtest("LDAP server is reachable"):
              machine.wait_for_open_port(${toString result.port})
              machine.succeed(
                  "ldapsearch -x -H ldap://${result.host}:${toString result.port}"
                  + " -D '${result.bindDN}'"
                  + " -y ${result.bindPasswordFile}"
                  + " -b '${result.baseDN}' '(objectClass=*)' dn"
              )

          with subtest("Requested group exists"):
              # Wait for the group provisioning service to complete.
              machine.wait_until_succeeds(
                  "ldapsearch -x -H ldap://${result.host}:${toString result.port}"
                  + " -D '${result.bindDN}'"
                  + " -y ${result.bindPasswordFile}"
                  + " -b '${result.groupBaseDN}' '(cn=${containers.machine.test.group})' dn"
                  + " | grep -q 'dn:'"
              )
              output = machine.succeed(
                  "ldapsearch -x -H ldap://${result.host}:${toString result.port}"
                  + " -D '${result.bindDN}'"
                  + " -y ${result.bindPasswordFile}"
                  + " -b '${result.groupBaseDN}' '(cn=${containers.machine.test.group})' dn"
              )
              print(f"Group search result: {output}")
        '';
    };
}
