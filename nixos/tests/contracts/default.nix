{ runTest }:
{
  cross-node = runTest ./cross-node.nix;
  microservice-explore-A = runTest ./microservice-explore-A.nix;
  microservice-explore-B = runTest ./microservice-explore-B.nix;
  microservice-explore-C = runTest ./microservice-explore-C.nix;
}
