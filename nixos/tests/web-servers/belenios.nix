{ pkgs, lib, ... }: {
  name = "belenios";
  meta = {
    maintainers = with lib.maintainers; [ kiara ];
  };

  nodes.machine = { pkgs, ... }: {
    services.belenios = {
      enable = true;
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("belenios.socket")
    machine.wait_for_open_port(8001)
    response = machine.wait_until_succeeds("curl -fsS localhost:8001")
    assert "Hello NixOS!" in response
    machine.wait_for_unit("belenios.service")
  '';
}
