# Contracts {#contracts}

A contract is an interface between a *consumer* and a *provider* of a resource.
The consumer tells what it needs in a `request`.
The provider supplies the resource and tells the consumer about it in a `response`.

Each contract type has an interface module that declares the options `request` and `response`.
The consumer and the provider import the same interface module.
Thus, a consumer can use each provider of the contract type, and does not depend on one specific provider.

Status: experimental. The interfaces can change.

## File secrets {#contracts-file-secrets}

The file secrets contract gives a secret to a consumer in a file with given permissions.
Its interface module is `nixos/modules/contracts/file-secrets.nix`, with these options:

- `request.mode`: the mode that the file must have. The default is `"0400"`.
- `request.owner`: the user that must own the file.
- `request.group`: the group that must own the file.
- `response.path`: the path of the file.

## Consumers {#contracts-consumers}

A consumer declares an option with a submodule type that imports the interface module.
With option declaration merging, the consumer can add a `default` to an option of the interface, or make it `readOnly`.

This example is a simplified version of `services.stash.passwordFile`:

```nix
{
  options.services.stash.passwordFile = lib.mkOption {
    type = lib.types.submodule {
      imports = [ ../../contracts/file-secrets.nix ];
      options.request = lib.mkOption {
        default = { };
        type = lib.types.submodule {
          options.owner = lib.mkOption {
            default = cfg.user;
            readOnly = true;
          };
        };
      };
    };
  };
}
```

The consumer reads the path of the file from `cfg.passwordFile.response.path`.

A consumer can also accept a plain path, with `types.oneOf [ types.path contractType ]`.

## Providers {#contracts-providers}

A provider declares an attribute set of submodules that import the same interface module.
The provider sets a `default` for each option in `response`, and uses the options in `request` to make the resource.

Options that are specific to the provider go in `providerOptions`.
Do not add other options at the top level of an entry. That level is for the contract.

This example is a simplified version of `testing.hardcoded-secret.fileSecrets`:

```nix
{
  options.testing.hardcoded-secret.fileSecrets = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          imports = [ ../contracts/file-secrets.nix ];
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

At activation, this provider writes each file with the mode, owner and group from `request`.
It puts the content of the secret in the Nix store, so use it only for tests.

## Connect a consumer to a provider {#contracts-connect}

The user connects each consumer option to a provider entry.
The user sets the `request` of the provider entry from the consumer, and the `response` of the consumer from the provider entry:

```nix
{ config, ... }:
{
  services.stash.passwordFile.response =
    config.testing.hardcoded-secret.fileSecrets.stash-password.response;

  testing.hardcoded-secret.fileSecrets.stash-password = {
    request = config.services.stash.passwordFile.request;
    providerOptions.content = "MyPassword";
  };
}
```

To use a different provider, change these two definitions.
