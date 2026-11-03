# Contracts {#contracts}

A contract is an interface between a *consumer* and a *provider* of a resource.
The consumer tells what it needs in a `request`.
The provider supplies the resource and tells the consumer about it in a `response`.

Each contract type is an option `contracts.<type>`.
Its entries in `instances` have the options `request` and `response` of the contract type.
The consumer and the provider use the same entries.
Thus, a consumer can use each provider of the contract type, and does not depend on one specific provider.

Status: experimental. The interfaces can change.

This chapter describes how contracts work in general.
The examples use the file secrets contract type [](#opt-contracts.fileSecrets), its consumer `services.stash` and its test provider `testing.hardcoded-secret`.
For the `request` and `response` options of a contract type, refer to the options of that contract type, for example [](#opt-contracts.fileSecrets.instances).
For the behavior of a provider, refer to the options of the provider in `instances.<name>.providerOptions`, for example [](#opt-contracts.fileSecrets.instances._name_.providerOptions.hardcoded-secret).

## Consumers {#contracts-consumers}

A consumer sends a `request` to an entry of `contracts.<type>.instances`, and reads the `response` of that entry.
Each name must be unique for all consumers, for example `<consumer>-<option>`.

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

A provider adds an entry with its name to `contracts.<type>.providers`, for example `contracts.fileSecrets.providers.hardcoded-secret = { };`.
The user selects the provider with a reference to that entry, refer to [](#contracts-routing).
`contracts.<type>.providers.<provider>.instances` contains the entries of `instances` that the user sent to the provider.
The provider uses the `request` of each of these entries to make the resource.

The provider also declares options in `contracts.<type>.instances`.
These declarations merge with the declarations of the contract type:

- Its options for one entry go in `instances.<name>.providerOptions.<provider>`.
- It sets the `response` of each entry in `providers.<provider>.instances`, with `lib.mkOptionDefault`, thus a definition of the user replaces it.

Do not set `description` in a declaration of an option of the contract type: the contract type sets it, and a second `description` is an error.

Do not add other options at the top level of an entry. That level is for the contract.
The contract type declares the options at the top level, and a new version of the contract type can add an option there.
The contract type and the providers do not agree on the names of the provider options.
If a provider declares an option at the top level, a new option of the contract type can have the same name, and the two declarations then conflict.
In `providerOptions.<provider>`, an option of the provider cannot conflict with an option of the contract type.

Example, a simplified version of the provider `testing.hardcoded-secret`:

```nix
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.testing.hardcoded-secret;
  provider = config.contracts.fileSecrets.providers.hardcoded-secret;
in
{
  options.contracts.fileSecrets.instances = mkOption {
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options.providerOptions.hardcoded-secret = mkOption {
            description = "Options of the provider `testing.hardcoded-secret` for this entry.";
            default = { };
            type = types.submodule {
              options.content = mkOption { type = types.str; };
            };
          };
          config.response = lib.mkIf (provider.instances ? ${name}) (
            lib.mkOptionDefault { path = "${cfg.directory}/${name}"; }
          );
        }
      )
    );
  };

  config = {
    contracts.fileSecrets.providers.hardcoded-secret = { };
    systemd.services = lib.mapAttrs' (
      name: instance:
      lib.nameValuePair "hardcodedsecret_${name}" {
        # Writes `instance.providerOptions.hardcoded-secret.content` to `instance.response.path`,
        # with the permissions in `instance.request`.
      }
    ) provider.instances;
  };
}
```

## Connect a consumer to a provider {#contracts-connect}

The user selects the provider of each entry, refer to [](#contracts-routing).
The user can also connect an entry manually, without a provider in `providers`.
Then the user sets the `provider` of the entry to `null`, makes the resource from the `request`, and sets the `response`.
Example, with the consumer from the example before, and a secret file that the user makes:

```nix
{
  services.stash.passwordFromContract = true;

  contracts.fileSecrets.instances.stash-password = {
    provider = null;
    response.path = "/run/keys/stash-password";
  };
}
```

## Contract types {#contracts-types}

The contract types of NixOS are in `nixos/modules/contracts`.
Each contract type is a module that declares the option `contracts.<type>` with `lib.contract.mkContractOption`, and sets `meta.maintainers`.
`mkContractOption` takes the `name` of the contract type, a `description`, and an `interface` module that declares the options `request` and `response`.
Each entry of `instances` imports the `interface` module.

Example, a simplified version of `nixos/modules/contracts/file-secrets.nix`:

```nix
{ lib, ... }:
{
  meta.maintainers = with lib.maintainers; [ ibizaman ];
  options.contracts.fileSecrets = lib.contract.mkContractOption {
    name = "fileSecrets";
    description = "A secret in a file, with given permissions.";
    interface.options = {
      request = lib.mkOption {
        default = { };
        type = lib.types.submodule {
          options.owner = lib.mkOption { type = lib.types.str; };
        };
      };
      response = lib.mkOption {
        type = lib.types.submodule {
          options.path = lib.mkOption { type = lib.types.path; };
        };
      };
    };
  };
}
```

To add a contract type, add a file in `nixos/modules/contracts`, and import it in `nixos/modules/contracts/default.nix`.

The options of a contract type do not depend on `config`, thus a module can add a contract type without changes to other modules.

## Route requests to a provider {#contracts-routing}

For each contract type, `contracts.<type>` has these options:

- `instances.<name>`: an entry with a `request` from a consumer, the `response` for the consumer, the `provider` that gets the `request` and sets the `response`, and `providerOptions`, the options of the providers for this entry.
  The default of `provider` is `defaultProvider`.
  A definition of `response` by the user replaces the response of the provider.
- `providers.<provider>`: an entry for each provider in the configuration.
- `defaultProvider`: the provider that gets the requests.

The value of `provider` and `defaultProvider` is `null` or an entry of `providers` of the same contract type, for example `config.contracts.fileSecrets.providers.hardcoded-secret`.
Thus, the name of a provider that the configuration does not import is an error, because that attribute is missing.
The module system also rejects a string, and a provider of a different contract type.

The default of `defaultProvider` is `null`, thus by default no provider gets the requests, and the `response` of an entry has no value.
This is because a provider such as `testing.hardcoded-secret` is not safe for production.
The user selects the provider, and sets the options of the provider for each request.
Example, with the consumer `services.stash` and the provider `testing.hardcoded-secret`:

```nix
{ config, ... }:
{
  contracts.fileSecrets = {
    defaultProvider = config.contracts.fileSecrets.providers.hardcoded-secret;
    instances.stash-password.providerOptions.hardcoded-secret.content = "MyPassword";
  };
  services.stash.passwordFromContract = true;
}
```

To use a different provider, change `defaultProvider`, and set the options of that provider.

To send one entry to a different provider, set `instances.<name>.provider` to that provider:

```nix
{ config, ... }:
{
  contracts.fileSecrets.instances.stash-password.provider =
    config.contracts.fileSecrets.providers.other-provider;
}
```

To connect one entry manually, set `instances.<name>.provider` to `null`, as in [](#contracts-connect).

Another module system can import the module of a contract type, for example `nixos/modules/contracts/file-secrets.nix` in a submodule.
That module sets `meta.maintainers`, thus the module system must also import `nixos/modules/misc/meta.nix`, or declare `meta.maintainers`.
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
