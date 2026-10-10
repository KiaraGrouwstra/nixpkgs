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
Its interface module is `lib.contracts.fileSecrets.interface`, with these options:

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
      imports = [ lib.contracts.fileSecrets.interface ];
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

At activation, this provider writes each file with the mode, owner and group from `request`.
It puts the content of the secret in the Nix store, so use it only for tests.

## Contract types {#contracts-types}

`lib.contracts` contains the contract types of nixpkgs.
Each contract type has `meta.description`, `meta.maintainers` and an `interface` module.

The option [](#opt-contractTypes) contains the contract types that a configuration can use.
In NixOS, it contains each contract type in `lib.contracts`.
To add a contract type, write its `meta` and `interface` in a new file in `lib/contracts/definitions`, and add that file to `lib/contracts/definitions/default.nix`.

The routing module is `lib.contract.module`.
It does not depend on NixOS, so other module systems can also import it.

## Route requests to a provider {#contracts-routing}

For each contract type, [](#opt-contracts) sends the requests of consumers to a provider, and sends the responses back:

- `contracts.<type>.want.<name>`: an entry with a `request` from a consumer.
  Each name must be unique for all consumers, for example `<consumer>-<option>`.
- `contracts.<type>.providers.<provider>`: an attribute set with an entry for each request that the provider fulfills.
- `contracts.<type>.defaultProvider`: the name of the provider that gets the requests.
- `contracts.<type>.providerRequests.<provider>`: the requests that a provider must fulfill.
  This is `want` for `defaultProvider`, and `{ }` for the other providers.
- `contracts.<type>.results.<name>`: the `response` from `defaultProvider` for each entry in `want`.

A provider reads `providerRequests.<provider>`, and sets `providers.<provider>` to its entries:

```nix
{ config, ... }:
{
  testing.hardcoded-secret.fileSecrets = config.contracts.fileSecrets.providerRequests.hardcoded-secret;
  contracts.fileSecrets.providers.hardcoded-secret = config.testing.hardcoded-secret.fileSecrets;
}
```

The user sends the `request` of a consumer option to `want`, and sets the `response` of the option from `results`.
The user also selects the provider, and sets the options of the provider for each request:

```nix
{ config, ... }:
{
  contracts.fileSecrets.want.stash-passwordFile = {
    inherit (config.services.stash.passwordFile) request;
  };
  services.stash.passwordFile.response = config.contracts.fileSecrets.results.stash-passwordFile;

  contracts.fileSecrets.defaultProvider = "hardcoded-secret";
  testing.hardcoded-secret.fileSecrets.stash-passwordFile.providerOptions.content = "MyPassword";
}
```

To use a different provider, change `defaultProvider`, and set the options of that provider.
