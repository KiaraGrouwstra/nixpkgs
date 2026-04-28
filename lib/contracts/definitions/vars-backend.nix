{
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (types)
    attrsOf
    bool
    str
    submodule
    ;
in
{
  meta = {
    description = ''
      Contract for vars storage backends. A backend determines where and how
      generated files are stored and retrieved, returning the final file paths.
    '';
    maintainers = with lib.maintainers; [
      kiara
    ];
  };
  interface = {
    request = {
      files = mkOption {
        description = ''
          Files to be stored by the backend, with their metadata.
          Keys are file names matching those declared in the generateFiles request.
        '';
        type = attrsOf (submodule {
          options = {
            secret = mkOption {
              description = "Whether the file contains sensitive data.";
              type = bool;
              default = true;
            };
            owner = mkOption {
              description = "Unix user that must own the file.";
              type = str;
              default = "root";
            };
            group = mkOption {
              description = "Unix group that must own the file.";
              type = str;
              default = "root";
            };
            mode = mkOption {
              description = "File permissions as an octal string.";
              type = str;
              default = "0400";
            };
          };
        });
      };
    };
    result = {
      files = mkOption {
        description = ''
          Final provisioned paths per file.
        '';
        type = attrsOf (submodule {
          options.path = mkOption {
            description = "Path to the provisioned file on the target system.";
            type = str;
          };
        });
      };
    };
  };
}
