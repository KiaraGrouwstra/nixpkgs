{
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (types) str;
in
{
  meta = {
    description = ''
      Contract for SSL certificate provisioning where a consumer
      requests a certificate and a provider generates it.
    '';
    maintainers = with lib.maintainers; [
      ibizaman
    ];
  };
  interface = {
    request = {
      domain = mkOption {
        description = ''
          Domain name for which the certificate is requested.
        '';
        type = str;
        example = "example.com";
      };
    };
    result = {
      cert = mkOption {
        description = "Path to the certificate file.";
        type = str;
      };
      key = mkOption {
        description = "Path to the private key file.";
        type = str;
      };
      systemdService = mkOption {
        description = ''
          Systemd oneshot service that generates the certificate.
          Ends with the `.service` suffix.
        '';
        type = str;
        example = "cert-generator.service";
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
      name = "contracts_ssl_${name}";
      nodes.machine =
        { config, ... }:
        {
          imports = extraModules;
          options.test.domain = mkOption {
            type = str;
            default = "test.local";
          };
          config = lib.setAttrByPath providerRoot {
            request.domain = config.test.domain;
          };
        };
      testScript =
        { nodes, ... }:
        let
          cfg = nodes.machine;
          inherit (lib.getAttrFromPath providerRoot nodes.machine) result;
        in
        ''
          with subtest("Generate certificate"):
              machine.succeed("systemctl start ${result.systemdService}")

          with subtest("Certificate file exists"):
              machine.succeed("test -f ${result.cert}")

          with subtest("Key file exists"):
              machine.succeed("test -f ${result.key}")

          with subtest("Certificate is valid for requested domain"):
              subject = machine.succeed("openssl x509 -in ${result.cert} -noout -subject").strip()
              print(f"Certificate subject: {subject}")
              assert "${cfg.test.domain}" in subject, f"domain not in subject: {subject}"

          with subtest("Key matches certificate"):
              cert_pub = machine.succeed("openssl x509 -in ${result.cert} -noout -pubkey").strip()
              key_pub = machine.succeed("openssl pkey -in ${result.key} -pubout").strip()
              assert cert_pub == key_pub, "key does not match certificate"
        '';
    };
}
