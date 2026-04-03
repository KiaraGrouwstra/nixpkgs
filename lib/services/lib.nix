{ lib, ... }:
let
  inherit (lib)
    concatLists
    mapAttrsToList
    showOption
    types
    ;
in
rec {
  flattenMapServicesConfigToList =
    f: loc: config:
    f loc config
    ++ concatLists (
      mapAttrsToList (
        k: v:
        flattenMapServicesConfigToList f (
          loc
          ++ [
            "services"
            k
          ]
        ) v
      ) config.services
    );

  getWarnings = flattenMapServicesConfigToList (
    loc: config: map (msg: "in ${showOption loc}: ${msg}") config.warnings
  );

  getAssertions = flattenMapServicesConfigToList (
    loc: config:
    map (ass: {
      message = "in ${showOption loc}: ${ass.message}";
      assertion = ass.assertion;
    }) config.assertions
  );

  /**
    Entrypoint for integrating modular services into a containing module system.

    Each containing system (NixOS, ...) calls `configure` to
    obtain a `serviceSubmodule` type for its services option. The returned submodule
    includes the portable service base, contract integration, and any
    service-manager-specific modules passed via `extraRootModules`.

    **Implementing for a new system** (e.g. home-manager, nix-darwin):

    ```nix
    # darwin/modules/services/system.nix
    { lib, config, pkgs, ... }:
    let
      portable-lib = import <nixpkgs/lib/services/lib.nix> { inherit lib; };

      modularServiceConfiguration = portable-lib.configure {
        serviceManagerPkgs = pkgs;
        extraRootModules = [
          ./launchd-service.nix    # launchd-specific options (plist generation, etc.)
        ];
        inherit (config) contracts;
        upstreamContractTypes = config.contractTypes;
      };
    in
    {
      imports = [
        ./contracts-bridge.nix   # collects want/providers from services (see below)
      ];

      options.services = lib.mkOption {
        type = lib.types.attrsOf modularServiceConfiguration.serviceSubmodule;
        default = { };
      };

      config = {
        # Convert service tree → launchd plists, assertions, etc.
        # (analogous to how NixOS converts to systemd units)
        launchd.agents = ...;
        assertions = ...;
        warnings = ...;
      };
    }
    ```

    The bridge module collects `contracts.<type>.want` and `contracts.<type>.providers`
    from all services and merges them into the containing system's contract namespace.
    See `nixos/modules/system/service/nixos-contracts-bridge.nix` for the reference.

    lib.services.configure :: AttrSet -> { serviceSubmodule :: SubmoduleType }

    # Inputs

    `serviceManagerPkgs`

    : A Nixpkgs instance used for built-in logic such as converting
    `configData.<path>.text` to a store path.

    `extraRootModules`

    : Modules to be loaded into the "root" service submodule, but not
    into its sub-`services`. That's the modules' own responsibility.
    Typically contains service-manager-specific option modules
    (e.g. systemd unit options, launchd plist options).

    `extraRootSpecialArgs`

    : Fixed module arguments provided alongside `extraRootModules`.

    `contracts`

    : The containing system's `config.contracts` - passed through to
    `_upstreamContracts` so services can read aggregated requests and results.

    `upstreamContractTypes`

    : The containing system's `config.contractTypes` - propagated into
    each service's module system so user-defined contract types are available.

    # Output

    An attribute set.

    `serviceSubmodule`: a Module System option type which is a `submodule` with the portable modules and this function's inputs loaded into it.
  */
  configure =
    {
      serviceManagerPkgs,
      extraRootModules ? [ ],
      extraRootSpecialArgs ? { },
      contracts ? { },
      # All NixOS-level contract type definitions (meta + interface), so services
      # can use `contracts.<type>.*` for both lib-level and user-defined contract types.
      upstreamContractTypes ? { },
    }:
    let
      # Seeds the service's module system with upstream contract state.
      #
      # `_upstreamContracts` connects the service's contract namespace to a
      # containing system's resolved contracts. This gives services
      # access to aggregated `requests` and resolved `defaultProvider`/`results`.
      #
      # Write-side options (`want`, `providers`) remain local to the service.
      # `nixos-contracts-bridge` reads these and lifts them to the containing system.
      upstreamSeedModule =
        { lib, ... }:
        {
          config = {
            # Propagate contract type definitions so user-defined types are available.
            contractTypes = lib.mapAttrs (_: contract: {
              inherit (contract) meta interface;
            }) upstreamContractTypes;
            # Connect read-side contract options to the containing system.
            _upstreamContracts = contracts;
          };
        };
      modules = [
        (lib.modules.importApply ./service.nix { pkgs = serviceManagerPkgs; })
      ];
      serviceSubmodule = types.submoduleWith {
        class = "service";
        modules = modules ++ [ upstreamSeedModule ] ++ extraRootModules;
        specialArgs = extraRootSpecialArgs;
      };
    in
    {
      inherit serviceSubmodule;
    };
}
