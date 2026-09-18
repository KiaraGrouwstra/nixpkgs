# Tests in: ./tests/config-files.nix
{ lib, pkgs }:

/**
  A module system evaluation that maps options to the configuration files of a
  program.

  A program takes its configuration from one or more files. The options that
  describe that configuration, and the code that writes the files, belong
  together, and they do not depend on NixOS. This function puts that pair in a
  module that any system is able to evaluate.

  Write the module next to the package, and expose it in `passthru`. A NixOS
  module then puts `module` next to the options that only NixOS has, and does
  not repeat the declarations. A system that is not NixOS calls `eval` and gets
  the same files.

  The module carries `pkgs` itself, because a submodule does not inherit the
  module arguments of the evaluation that holds it.

  The evaluation adds a `files` option, of the type that `pkgs.files` gives,
  and a read-only `directory` output that holds those files. A module sets
  `files`, and reads the options that it declares itself.

  # Inputs

  `name`
  : Name of the program. It is the prefix of the name of every derivation
    that the evaluation builds.

  `relativeTo`
  : Name of the directory that the files are relative to, for the
    documentation of `files.<name>.target`. Use the syntax of an option
    description.

  `modules`
  : Modules that declare the options of the program, and that set `files`
    from them.

  `extraFileModules`
  : Modules to add to every file, as `extraModules` of `pkgs.files`.

  # Type

  ```
  configFiles :: {
    name :: String,
    relativeTo :: String,
    modules :: [ Module ],
    extraFileModules :: [ Module ],
  } -> {
    module :: Module,
    type :: Type,
    eval :: ([ Module ] | Module) -> AttrSet,
    files :: { type :: Type, toDirectory :: String -> AttrsOf File -> Derivation },
  }
  ```

  # Outputs

  `module`
  : The whole configuration as one module. Add it to the module list of a
    submodule to put the configuration of the program next to the options of
    a larger module system evaluation, such as the `enable` option of a NixOS
    service.

  `type`
  : Module system type of the whole configuration. Declare an option of this
    type to put the configuration of the program in a larger module system
    evaluation that adds no options of its own.

  `eval`
  : Function that takes modules and returns the configuration of the
    evaluation. Use this outside of a module system evaluation. The result
    holds the options that the program declares, and `files` and `directory`.

  `files`
  : The `pkgs.files` result that `files` uses. Use it to build a directory of
    a subset of the files.

  # Examples
  :::{.example}
  ## `pkgs.configFiles` usage example

  The package exposes the module:

  ```nix
  # pkgs/by-name/my/my-program/package.nix
  stdenv.mkDerivation {
    passthru.config = pkgs.configFiles {
      name = "my-program";
      relativeTo = "{file}`/etc/my-program`";
      modules = [ ./config-module.nix ];
    };
  }
  ```

  ```nix
  # pkgs/by-name/my/my-program/config-module.nix
  { lib, config, pkgs, ... }:
  let
    format = pkgs.formats.ini { };
  in
  {
    options.settings = lib.mkOption {
      type = format.type;
      default = { };
      description = "Configuration of my-program.";
    };

    config.files."main.ini".source = format.generate "main.ini" config.settings;
  }
  ```

  A NixOS module puts the module next to its own options, and takes the files
  from it:

  ```nix
  {
    options.services.myProgram = lib.mkOption {
      default = { };
      description = "my-program, a program.";
      type = lib.types.submoduleWith {
        modules = [
          pkgs.my-program.config.module
          { options.enable = lib.mkEnableOption "my-program"; }
        ];
      };
    };

    config = lib.mkIf config.services.myProgram.enable {
      environment.etc."my-program".source = config.services.myProgram.directory;
    };
  }
  ```

  A system that is not NixOS builds the same directory:

  ```nix
  (pkgs.my-program.config.eval { settings.verbose = true; }).directory
  ```
  :::
*/
{
  name,
  relativeTo ? "the configuration directory of the program",
  modules ? [ ],
  extraFileModules ? [ ],
}:
let
  files = pkgs.files {
    namePrefix = name;
    inherit relativeTo;
    extraModules = extraFileModules;
  };

  base =
    { config, ... }:
    {
      options = {
        files = lib.mkOption {
          type = lib.types.attrsOf files.type;
          default = { };
          description = ''
            Configuration files of the program. The modules of the program set
            this from the options that they declare.
          '';
        };

        directory = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          description = ''
            Directory that holds the files of `files`, each at its own
            `target`.
          '';
        };
      };

      config.directory = files.toDirectory "${name}-config" config.files;
    };
in
rec {
  inherit files;

  module = {
    imports = [ base ] ++ modules;

    # A submodule does not inherit the module arguments of the evaluation that
    # holds it. The modules of the program need `pkgs` to build the files, so
    # the module gives it to them itself.
    _module.args.pkgs = lib.mkDefault pkgs;
  };

  type = lib.types.submoduleWith {
    modules = [ module ];
  };

  eval =
    modules:
    (lib.evalModules {
      modules = [ module ] ++ lib.toList modules;
    }).config;
}
