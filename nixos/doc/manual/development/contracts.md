# Contracts {#contracts}

A contract is an interface between a *consumer* and a *provider* of a resource.
The consumer tells what it needs in a `request`.
The provider supplies the resource and tells the consumer about it in a `response`.

Each contract type has an interface module that declares the options `request` and `response`.
The consumer and the provider import the same interface module.
Thus, a consumer can use each provider of the contract type, and does not depend on one specific provider.

Status: experimental. The interfaces can change.

This chapter describes how contracts work in general.
The examples use the credential secrets contract type `lib.contracts.credentialSecrets`, its consumer `services.stash` and its test provider `testing.hardcoded-secret`.
For the `request` and `response` options of a contract type and the behavior of a provider, refer to the options of the provider, for example [](#opt-testing.hardcoded-secret.credentialSecrets).

## Consumers {#contracts-consumers}

A consumer declares an option with a submodule type that imports the interface module.
With option declaration merging, the consumer can add a `default` to an option of the interface, or make it `readOnly`.

Example, a simplified version of the consumer option `services.stash.passwordSecret`:

```nix
{
  options.services.stash.passwordSecret = lib.mkOption {
    type = lib.types.submodule {
      imports = [ lib.contracts.credentialSecrets.interface ];
      options.request = lib.mkOption {
        default = { };
        type = lib.types.submodule {
          options.unit = lib.mkOption {
            default = "stash.service";
            readOnly = true;
          };
          options.id = lib.mkOption {
            default = "password";
            readOnly = true;
          };
        };
      };
    };
  };
}
```

The consumer reads the resource from `response`.
In the example, the source of the credential is `cfg.passwordSecret.response.path`.

A consumer can keep an option without a contract next to the contract option.
For example, `services.stash.passwordFile` takes a plain path.
If the user sets `services.stash.passwordSecret`, the module sets `passwordFile` to `cfg.passwordSecret.response.path` with `lib.mkDefault`.
A consumer can also accept a value with or without a contract in one option, with `types.oneOf [ types.path contractType ]`.

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

Example, a simplified version of the provider option `testing.hardcoded-secret.credentialSecrets`:

```nix
{
  options.testing.hardcoded-secret.fileSecrets = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          imports = [ lib.contracts.credentialSecrets.interface ];
          options.response = lib.mkOption {
            default = { };
            type = lib.types.submodule {
              options.path = lib.mkOption { default = "${cfg.directory}/${name}.sock"; };
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

## Connect a consumer to a provider {#contracts-connect}

The user connects each consumer option to a provider entry.
The user sets the `request` of the provider entry from the consumer, and the `response` of the consumer from the provider entry.
Example, with the consumer and the provider from the examples before:

```nix
{ config, ... }:
{
  services.stash.passwordSecret.response =
    config.testing.hardcoded-secret.credentialSecrets."stash-password".response;

  testing.hardcoded-secret.credentialSecrets."stash-password" = {
    request = config.services.stash.passwordSecret.request;
    providerOptions.content = "MyPassword";
  };
}
```

To use a different provider, change these two definitions.

## Secrets {#contracts-secrets}

There are two contract types for secrets:

- `lib.contracts.credentialSecrets`, for a consumer that is a systemd unit.
  The consumer loads the secret with `LoadCredential=`.
  The source can be a regular file or an `AF_UNIX` stream socket.
  With a socket, the provider does not write the secret to a file, and it can examine which unit and credential ID connects.
- `lib.contracts.fileSecrets`, for a consumer that must read the secret from a file.
  The file has the owner, group and mode from the request.

Use `credentialSecrets` if the consumer is a systemd unit.
A `fileSecrets` provider entry can also give the response of a `credentialSecrets` consumer, because both responses have a `path`, and a regular file is a valid source of a credential.
Set the request of the file so that only root can read it.
The example uses the defaults of the provider, owner and group `root` and mode `0400`:

```nix
{ config, ... }:
{
  services.stash.passwordSecret.response =
    config.testing.hardcoded-secret.fileSecrets."stash-password".response;

  testing.hardcoded-secret.fileSecrets."stash-password".providerOptions.content = "MyPassword";
}
```
