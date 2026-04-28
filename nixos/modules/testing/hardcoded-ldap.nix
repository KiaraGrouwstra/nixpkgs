{
  config,
  lib,
  options,
  pkgs,
  ...
}:
let
  cfg = config.testing.hardcoded-ldap;

  inherit (lib)
    contracts
    mkOption
    ;
  inherit (lib.types)
    str
    submodule
    ;
  contract = "ldap";
  inherit (contracts.${contract}) mkProviderType;

  baseDN = "dc=test,dc=local";
  bindDN = "cn=admin,${baseDN}";
  bindPassword = "testpassword";
  groupBaseDN = "ou=groups,${baseDN}";
  userBaseDN = "ou=people,${baseDN}";
in
{
  options.testing.hardcoded-ldap = mkOption {
    description = ''
      Hardcoded LDAP provider for testing.
      Runs openldap with a minimal directory containing requested groups.
    '';
    type = submodule {
      options = {
        port = mkOption {
          description = "Port for the LDAP server.";
          type = lib.types.port;
          default = 3890;
        };
        passwordFile = mkOption {
          description = "Path to the bind password file.";
          type = str;
          default = "/run/hardcoded-ldap/password";
        };
        ${contract} = mkOption {
          description = "Instances of the ldap contract.";
          default = config.contracts.${contract}.requests;
          defaultText = lib.literalExpression "config.contracts.${contract}.requests";
          type = mkProviderType {
            fulfill' = _: {
              host = "127.0.0.1";
              port = cfg.port;
              inherit
                baseDN
                userBaseDN
                groupBaseDN
                bindDN
                ;
              bindPasswordFile = cfg.passwordFile;
            };
          };
        };
      };
    };
  };

  config = {
    contracts.${contract}.providers.hardcoded-ldap.module = options.testing.hardcoded-ldap;

    services.openldap = {
      enable = true;
      urlList = [ "ldap://127.0.0.1:${toString cfg.port}" ];
      settings = {
        attrs = {
          olcLogLevel = "stats";
        };
        children = {
          "cn=schema".includes = [
            "${pkgs.openldap}/etc/schema/core.ldif"
            "${pkgs.openldap}/etc/schema/cosine.ldif"
            "${pkgs.openldap}/etc/schema/inetorgperson.ldif"
          ];
          "olcDatabase={1}mdb" = {
            attrs = {
              objectClass = [
                "olcDatabaseConfig"
                "olcMdbConfig"
              ];
              olcDatabase = "{1}mdb";
              olcDbDirectory = "/var/lib/openldap/data";
              olcSuffix = baseDN;
              olcRootDN = bindDN;
              olcRootPW = bindPassword;
            };
          };
        };
      };
      declarativeContents.${baseDN} =
        let
          groupEntries =
            lib.concatMapNestedAttrs' (options.testing.hardcoded-ldap.type.getSubOptions [ ]).${contract}.type
              (
                _path: instance:
                let
                  inherit (instance) request;
                in
                {
                  ${request.group} = ''
                    dn: cn=${request.group},${groupBaseDN}
                    objectClass: groupOfNames
                    cn: ${request.group}
                    member: ${bindDN}
                  '';
                }
              )
              cfg.${contract};
        in
        ''
          dn: ${baseDN}
          objectClass: top
          objectClass: dcObject
          objectClass: organization
          o: Test

          dn: ${userBaseDN}
          objectClass: organizationalUnit
          ou: people

          dn: ${groupBaseDN}
          objectClass: organizationalUnit
          ou: groups

          ${lib.concatStringsSep "\n" (lib.attrValues groupEntries)}
        '';
    };

    system.activationScripts.hardcoded-ldap-password = ''
      mkdir -p "$(dirname "${cfg.passwordFile}")"
      printf '%s' "${bindPassword}" > "${cfg.passwordFile}"
      chmod 0400 "${cfg.passwordFile}"
    '';
  };
}
