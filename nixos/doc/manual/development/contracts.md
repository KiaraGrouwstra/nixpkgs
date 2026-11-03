# Contracts {#contracts}

A contract is an interface between a *consumer* and a *provider* of a resource.
The consumer tells what it needs in a `request`.
The provider supplies the resource and tells the consumer about it in a `response`.

Each contract type has an interface module that declares the options `request` and `response`.
The consumer and the provider import the same interface module.
Thus, a consumer can use each provider of the contract type, and does not depend on one specific provider.

Status: experimental. The interfaces can change.

This chapter describes how contracts work in general.
The examples use the file secrets contract type `lib.contracts.fileSecrets`, its consumer `services.stash` and its test provider `testing.hardcoded-secret`.
For the `request` and `response` options of a contract type, refer to the options of that contract type in [](#opt-contracts), for example [](#opt-contracts.fileSecrets).
For the behavior of a provider, refer to the options of the provider, for example [](#opt-testing.hardcoded-secret.fileSecrets).

## Consumers {#contracts-consumers}

A consumer sends a `request` to an entry of `contracts.<type>.instances`, and reads the `response` of that entry.
Each name must be unique for all consumers, for example `<consumer>-<option>`.
The entry imports the interface module of the contract type, thus it has the options `request` and `response`.

Example, a simplified version of the consumer `services.stash`:

```nix
{ config, lib, ... }:
let
  cfg = config.services.stash;
in
{
  options.services.stash.passwordFromContract = lib.mkEnableOption "the password from the file secrets contract";

  config = lib.mkIf cfg.passwordFromContract {
    contracts.fileSecrets.instances.stash-password.request = {
      mode = "0400";
      owner = cfg.user;
      group = cfg.group;
    };
    services.stash.passwordFile = lib.mkDefault config.contracts.fileSecrets.instances.stash-password.response.path;
  };
}
```

The consumer sets the values of the `request` with a normal priority.
If the user sets a different value, the two definitions conflict.

A consumer can keep an option without a contract next to the contract.
For example, `services.stash.passwordFile` takes a plain path.
If the user sets `services.stash.passwordFromContract`, the module sets `passwordFile` to the path in the `response` with `lib.mkDefault`.

## Providers {#contracts-providers}

A provider declares an attribute set of submodules that import the same interface module.
The provider sets a `default` for each option in `response`, and uses the options in `request` to make the resource.

Options that are specific to the provider go in `providerOptions`.
Do not add other options at the top level of an entry. That level is for the contract.
The contract type declares the options at the top level, and a new version of the contract type can add an option there.
The contract type and the providers do not agree on the names of the provider options.
If a provider declares an option at the top level, a new option of the contract type can have the same name, and the two declarations then conflict.
In `providerOptions`, an option of the provider cannot conflict with an option of the contract type.
`request` and `response` are not in a namespace, because the contract type declares them.

Example, a simplified version of the provider option `testing.hardcoded-secret.fileSecrets`:

```nix
{
  options.testing.hardcoded-secret.fileSecrets = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          imports = [ lib.contracts.fileSecrets.interface ];
          options.response = lib.mkOption {
            default = { };
            type = lib.types.submodule {
              options.path = lib.mkOption { default = "${cfg.directory}/${name}"; };
            };
          };
          options.providerOptions = lib.mkOption {
            default = { };
            type = lib.types.submodule {
              options.content = lib.mkOption { type = lib.types.str; };
            };
          };
        }
      )
    );
  };
}
```

A provider also extends the type of `contracts.<type>`, so that the user can select it.
It adds its name to the types of `contracts.<type>.defaultProvider` and `contracts.<type>.instances.<name>.provider`.
It adds its options for one entry at `contracts.<type>.instances.<name>.providerOptions.<provider>`.
It sets the `response` of each entry with its name in `provider`, with `lib.mkOptionDefault`, thus a definition of the user replaces it.
These declarations merge with the declarations of the contracts module.
Do not set `description` in them: the contracts module sets it, and a second `description` is an error.

Example, a simplified version of the provider `testing.hardcoded-secret`:

```nix
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.testing.hardcoded-secret;
  providerType = types.nullOr (types.enum [ "hardcoded-secret" ]);
in
{
  options.contracts.fileSecrets.defaultProvider = mkOption { type = providerType; };
  options.contracts.fileSecrets.instances = mkOption {
    type = types.attrsOf (
      types.submodule (
        { name, config, ... }:
        {
          options.provider = mkOption { type = providerType; };
          options.providerOptions.hardcoded-secret = mkOption {
            description = "Options of the provider `testing.hardcoded-secret` for this entry.";
            default = { };
            type = types.submodule {
              options.content = mkOption { type = types.str; };
            };
          };
          config.response = lib.mkIf (config.provider == "hardcoded-secret") (
            lib.mkOptionDefault cfg.fileSecrets.${name}.response
          );
        }
      )
    );
  };

  config.testing.hardcoded-secret.fileSecrets =
    lib.mapAttrs
      (_: instance: {
        inherit (instance) request;
        providerOptions = instance.providerOptions.hardcoded-secret;
      })
      (
        lib.filterAttrs (
          _: instance: instance.provider == "hardcoded-secret"
        ) config.contracts.fileSecrets.instances
      );
}
```

## Connect a consumer to a provider {#contracts-connect}

The user selects the provider of each entry, refer to [](#contracts-routing).
The user can also connect an entry to a provider option manually.
Then the user sets the `provider` of the entry to `null`, sets the `request` of the provider entry from the entry, and sets the `response` of the entry from the provider entry.
Example, with the consumer and the provider from the examples before:

```nix
{ config, ... }:
{
  services.stash.passwordFromContract = true;

  contracts.fileSecrets.instances.stash-password = {
    provider = null;
    response = config.testing.hardcoded-secret.fileSecrets."stash-password".response;
  };

  testing.hardcoded-secret.fileSecrets."stash-password" = {
    request = config.contracts.fileSecrets.instances.stash-password.request;
    providerOptions.content = "MyPassword";
  };
}
```

## Contract types {#contracts-types}

`lib.contracts` contains the contract types of nixpkgs.
Each contract type has `meta.description`, `meta.maintainers` and an `interface` module.

The option [](#opt-contractTypes) contains the contract types that a configuration can use.
In NixOS, it contains each contract type in `lib.contracts`.
For each contract type, [](#opt-contracts) has an option with its `meta.description`, and with its `request` and `response` options under `instances.<name>`.
To add a contract type, write its `meta` and `interface` in a new file in `lib/contracts/definitions`, and add that file to `lib/contracts/definitions/default.nix`.

The routing module is `lib.contract.module`.
It does not depend on NixOS, so other module systems can also import it.

## Route requests to a provider {#contracts-routing}

For each contract type, [](#opt-contracts) has these options:

- `contracts.<type>.instances.<name>`: an entry with a `request` from a consumer, the `response` for the consumer, the `provider` that gets the `request` and sets the `response`, and `providerOptions`, the options of the providers for this entry.
  The default of `provider` is `defaultProvider`.
  A definition of `response` by the user replaces the response of the provider.
- `contracts.<type>.defaultProvider`: the name of the provider that gets the requests.

The type of `provider` and `defaultProvider` is `null` or one of the names that the providers in the configuration add.
Thus the module system rejects the name of a provider that the configuration does not import.

The default of `defaultProvider` is `null`, thus by default no provider gets the requests, and the `response` of an entry has no value.
This is because a provider such as `testing.hardcoded-secret` is not safe for production.
The user selects the provider, and sets the options of the provider for each request.
Example, with the consumer `services.stash` and the provider `testing.hardcoded-secret`:

```nix
{
  contracts.fileSecrets = {
    defaultProvider = "hardcoded-secret";
    instances.stash-password.providerOptions.hardcoded-secret.content = "MyPassword";
  };
  services.stash.passwordFromContract = true;
}
```

To use a different provider, change `defaultProvider`, and set the options of that provider.

To send one entry to a different provider, set `instances.<name>.provider` to that provider:

```nix
{
  contracts.fileSecrets.instances.stash-password.provider = "other-provider";
}
```

To connect one entry manually, set `instances.<name>.provider` to `null`, as in [](#contracts-connect).

Another module system can import `lib.contract.module`, for example in a submodule.
Each evaluation has its own `contracts`.
To connect an entry in a submodule to a provider of the configuration, set the `response` of the inner entry from an entry of the configuration, with the same `request`:

```nix
{ config, ... }:
{
  contracts.fileSecrets.instances.foo-password.request =
    config.services.foo.contracts.fileSecrets.instances.password.request;
  services.foo.contracts.fileSecrets.instances.password = {
    provider = null;
    inherit (config.contracts.fileSecrets.instances.foo-password) response;
  };
}
```
