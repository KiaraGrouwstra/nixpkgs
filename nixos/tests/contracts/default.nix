{ runTest }:
{
  chaining = runTest ./chaining.nix;
  collision = runTest ./collision-test.nix;
  cross-node = runTest ./cross-node.nix;
  cross-node-modular-services = runTest ./cross-node-modular-services.nix;
  cross-node-modular-services-direct = runTest ./cross-node-modular-services-direct.nix;
  database-modular-services = runTest ./database-modular-services.nix;
  filesecrets-hardcoded-secret = runTest ./filesecrets/hardcoded-secret.nix;
  modular-services = runTest ./modular-services.nix;
  nested-services = runTest ./nested-services.nix;
  nixos-provider-modular-consumer = runTest ./nixos-provider-modular-consumer.nix;
}
