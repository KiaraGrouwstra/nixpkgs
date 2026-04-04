{ lib, pkgs, ... }:

{
  name = "vector-modular-service";
  meta.maintainers = [ pkgs.lib.maintainers.happysalada ];

  nodes.machine =
    { config, pkgs, ... }:
    {
      # Use Vector as a modular service
      system.services.vector = {
        imports = [ pkgs.vector.services.default ];
        vector = {
          journaldAccess = true;
          settings = {
            sources = {
              journald.type = "journald";
              vector_metrics.type = "internal_metrics";
              vector_logs.type = "internal_logs";
            };
            sinks = {
              file = {
                type = "file";
                inputs = [
                  "journald"
                  "vector_logs"
                ];
                path = "/var/lib/vector/logs.log";
                encoding.codec = "json";
              };
              prometheus_exporter = {
                type = "prometheus_exporter";
                inputs = [ "vector_metrics" ];
                address = "[::]:9598";
              };
            };
          };
        };
      };

      # Derive firewall from modular service port metadata
      networking.firewall.allowedTCPPorts = lib.mapAttrsToList
        (_: p: p.port)
        (lib.filterAttrs (_: p: p.port != null && p.protocol == "tcp")
          config.system.services.vector.process.ports);
    };

  testScript = ''
    machine.wait_for_unit("vector.service")
    machine.wait_for_open_port(9598)
    machine.wait_until_succeeds("journalctl -o cat -u vector.service | grep 'version=\"${pkgs.vector.version}\"'")
    machine.wait_until_succeeds("journalctl -o cat -u vector.service | grep 'API is disabled'")
    machine.wait_until_succeeds("curl -sSf http://localhost:9598/metrics | grep vector_build_info")
    machine.wait_until_succeeds("curl -sSf http://localhost:9598/metrics | grep vector_component_received_bytes_total | grep journald")
    machine.wait_until_succeeds("curl -sSf http://localhost:9598/metrics | grep vector_utilization | grep prometheus_exporter")
    machine.wait_for_file("/var/lib/vector/logs.log")
  '';
}
