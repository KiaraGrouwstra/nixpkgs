# Run:
#   nix-instantiate --eval lib/services/test.nix
let
  lib = import ../.;

  inherit (lib) mkOption types;

  portable-lib = import ./lib.nix { inherit lib; };

  configured = portable-lib.configure {
    serviceManagerPkgs = throw "do not use pkgs in this test";
    extraRootModules = [ ];
    extraRootSpecialArgs = { };
  };

  dummyPkg =
    name:
    derivation {
      system = "dummy";
      name = name;
      builder = "/bin/false";
    };

  exampleConfig = {
    services = {
      service1 = {
        process = {
          argv = [
            "/usr/bin/echo" # *giggles*
            "hello"
          ];
          ports.http = {
            port = 8080;
          };
          ports.metrics = {
            port = 9090;
          };
          ports.dns = {
            port = 53;
            protocol = "udp";
          };
          ports.turn = {
            range = { from = 49152; to = 65535; };
            protocol = "udp";
          };
        };
        assertions = [
          {
            assertion = false;
            message = "you can't enable this for that reason";
          }
        ];
        warnings = [
          "The `foo' service is deprecated and will go away soon!"
        ];
      };
      service2 = {
        process = {
          # No meta.mainProgram, because it's supposedly an executable script _file_,
          # not a directory with a bin directory containing the main program.
          argv = [
            (dummyPkg "cowsay.sh")
            "world"
          ];
          user = {
            name = "cowsay";
            group = "cowsay";
          };
          directories = {
            state = "cowsay";
            logs = "cowsay";
          };
          capabilities = [ "net_bind_service" ];
          environment = {
            MOO = "true";
          };
          reload.signal = "SIGHUP";
        };
      };
      service3 = {
        process = {
          argv = [ "/bin/false" ];
        };
        services.exclacow = {
          process = {
            argv = [
              (lib.getExe (
                dummyPkg "cowsay-ng"
                // {
                  meta.mainProgram = "cowsay";
                }
              ))
              "!"
            ];
          };
          assertions = [
            {
              assertion = false;
              message = "you can't enable this for such reason";
            }
          ];
          warnings = [
            "The `bar' service is deprecated and will go away soon!"
          ];
        };
      };
    };
  };

  exampleEval = lib.evalModules {
    modules = [
      {
        options.services = mkOption {
          type = types.attrsOf configured.serviceSubmodule;
        };
      }
      exampleConfig
    ];
  };

  filterEval =
    config:
    lib.optionalAttrs (config ? process) {
      inherit (config) assertions warnings process;
    }
    // {
      services = lib.mapAttrs (k: filterEval) config.services;
    };

  test =
    assert
      filterEval exampleEval.config == {
        services = {
          service1 = {
            process = {
              argv = [
                "/usr/bin/echo"
                "hello"
              ];
              user = null;
              directories = { state = null; cache = null; runtime = null; logs = null; };
              capabilities = [ ];
              environment = { };
              reload = { signal = null; };
              ports = {
                http = { port = 8080; range = null; protocol = "tcp"; };
                metrics = { port = 9090; range = null; protocol = "tcp"; };
                dns = { port = 53; range = null; protocol = "udp"; };
                turn = { port = null; range = { from = 49152; to = 65535; }; protocol = "udp"; };
              };
            };
            services = { };
            assertions = [
              {
                assertion = true;
                message = "process.ports.dns: set either `port` or `range`, not both or neither.";
              }
              {
                assertion = true;
                message = "process.ports.http: set either `port` or `range`, not both or neither.";
              }
              {
                assertion = true;
                message = "process.ports.metrics: set either `port` or `range`, not both or neither.";
              }
              {
                assertion = true;
                message = "process.ports.turn: set either `port` or `range`, not both or neither.";
              }
              {
                assertion = false;
                message = "you can't enable this for that reason";
              }
            ];
            warnings = [
              "The `foo' service is deprecated and will go away soon!"
            ];
          };
          service2 = {
            process = {
              argv = [
                "${dummyPkg "cowsay.sh"}"
                "world"
              ];
              ports = { };
              user = { name = "cowsay"; group = "cowsay"; home = null; createHome = false; };
              directories = { state = "cowsay"; cache = null; runtime = null; logs = "cowsay"; };
              capabilities = [ "net_bind_service" ];
              environment = { MOO = "true"; };
              reload = { signal = "SIGHUP"; };
            };
            services = { };
            assertions = [ ];
            warnings = [ ];
          };
          service3 = {
            process = {
              argv = [ "/bin/false" ];
              user = null;
              directories = { state = null; cache = null; runtime = null; logs = null; };
              capabilities = [ ];
              environment = { };
              reload = { signal = null; };
              ports = { };
            };
            services.exclacow = {
              process = {
                argv = [
                  "${dummyPkg "cowsay-ng"}/bin/cowsay"
                  "!"
                ];
                user = null;
                directories = { state = null; cache = null; runtime = null; logs = null; };
                capabilities = [ ];
                environment = { };
                reload = { signal = null; };
                ports = { };
              };
              services = { };
              assertions = [
                {
                  assertion = false;
                  message = "you can't enable this for such reason";
                }
              ];
              warnings = [ "The `bar' service is deprecated and will go away soon!" ];
            };
            assertions = [ ];
            warnings = [ ];
          };
        };
      };

    assert
      portable-lib.getWarnings [ "service1" ] exampleEval.config.services.service1 == [
        "in service1: The `foo' service is deprecated and will go away soon!"
      ];

    assert
      portable-lib.getAssertions [ "service1" ] exampleEval.config.services.service1 == [
        {
          assertion = true;
          message = "in service1: process.ports.dns: set either `port` or `range`, not both or neither.";
        }
        {
          assertion = true;
          message = "in service1: process.ports.http: set either `port` or `range`, not both or neither.";
        }
        {
          assertion = true;
          message = "in service1: process.ports.metrics: set either `port` or `range`, not both or neither.";
        }
        {
          assertion = true;
          message = "in service1: process.ports.turn: set either `port` or `range`, not both or neither.";
        }
        {
          message = "in service1: you can't enable this for that reason";
          assertion = false;
        }
      ];

    assert
      portable-lib.getWarnings [ "service3" ] exampleEval.config.services.service3 == [
        "in service3.services.exclacow: The `bar' service is deprecated and will go away soon!"
      ];
    assert
      portable-lib.getAssertions [ "service3" ] exampleEval.config.services.service3 == [
        {
          message = "in service3.services.exclacow: you can't enable this for such reason";
          assertion = false;
        }
      ];

    "ok";

in
test
