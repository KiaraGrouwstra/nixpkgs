{
  name = "filebrowser";

  nodes.machine = {
    services.filebrowser = {
      enable = true;
      settings = {
        address = "localhost";
        port = 8080;
        database = "/var/lib/filebrowser/filebrowser.db";
        # This key is not a typed option, thus only the configuration file has it.
        baseURL = "/base";
      };
    };
  };

  testScript = ''
    machine.start()

    machine.wait_for_unit("filebrowser.service")
    machine.wait_for_open_port(8080)

    machine.succeed("curl --fail http://localhost:8080/")

    # Any path gives the HTML page with status 200, thus check the body.
    machine.succeed("curl --fail http://localhost:8080/base/health | grep -F '\"status\":\"OK\"'")

    machine.succeed("stat /var/lib/filebrowser/filebrowser.db")

    machine.shutdown()
  '';
}
