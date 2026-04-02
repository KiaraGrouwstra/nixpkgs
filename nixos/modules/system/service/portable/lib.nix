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
    This is the entrypoint for the portable part of modular services.

    It provides the various options that are consumed by service manager implementations.

    # Inputs

    `serviceManagerPkgs`: A Nixpkgs instance which will be used for built-in logic such as converting `configData.<path>.text` to a store path.

    `extraRootModules`: Modules to be loaded into the "root" service submodule, but not into its sub-`services`. That's the modules' own responsibility.

    `extraRootSpecialArgs`: Fixed module arguments that are provided in a similar manner to `extraRootModules`.

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
      nixosContractTypes ? { },
    }:
    let
      # Seeds the service's module system with:
      # 1. All NixOS contract type definitions (meta + interface only - computed
      #    `readOnly` fields are re-derived by the service's own module system).
      # 2. The NixOS-resolved `defaultProvider` for each contract type, so consumers
      #    can read `config.contracts.<type>.results` directly without needing the
      #    `contracts` specialArg.
      #
      # Only `defaultProvider` is injected (not `providers` or `want`) to avoid a
      # circular read by nixos-contracts-bridge, which reads `contracts.<type>.want`
      # from services to populate the NixOS-level `contracts.<type>.want`.
      nixosProviderSeedModule =
        { lib, ... }:
        {
          config = lib.mkMerge [
            {
              # Propagate contract type definitions so user-defined types are available.
              contractTypes = lib.mapAttrs (_: contract: {
                inherit (contract) meta interface;
              }) nixosContractTypes;
            }
            (lib.mkMerge (
              lib.mapAttrsToList (contractType: nixosContract: {
                contracts.${contractType}.defaultProvider = lib.mkDefault nixosContract.defaultProvider;
              }) contracts
            ))
          ];
        };
      modules = [
        (lib.modules.importApply ./service.nix { pkgs = serviceManagerPkgs; })
      ];
      serviceSubmodule = types.submoduleWith {
        class = "service";
        modules = modules ++ [ nixosProviderSeedModule ] ++ extraRootModules;
        specialArgs = extraRootSpecialArgs // {
          # Kept for provider services that read `contracts.<type>.requests`.
          inherit contracts;
        };
      };
    in
    {
      inherit serviceSubmodule;
    };
}
