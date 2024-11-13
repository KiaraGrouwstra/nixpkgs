{ config, lib, pkgs, ... }:
let
  cfg = config.services.belenios;
in {
  ###### interface

  options = {

    services.belenios = {
      enable = lib.mkEnableOption "Belenios, a verifiable voting system";

      # config = lib.mkOption {
      #   type = lib.types.lines;
      #   default = "";
      #   description = "Belenios config.";
      # };

      package = lib.mkPackageOption pkgs "belenios" { };

      denyRevote = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          Uncomment the following line to disable revoting.
          Note that the ability to revote is important as a (light) measure against coercion.
        '';
      };

      restrictedMode = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = ''
          Enables [restricted mode](https://gitlab.inria.fr/belenios/belenios/-/blob/master/doc/web.md),
          which restricts choices to ease security audits.
        '';
      };

      domain = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "belenios.example.org";
        description = ''
          Domain name used in Message-ID.
        '';
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        example = "0.0.0.0";
        description = ''
          Host to expose the web server on.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8001;
        example = 80;
        description = ''
          Port to expose the web server on.
        '';
      };

      maxUploadFileSize = lib.mkOption {
        type = lib.types.str;
        default = "5120kB";
        description = ''
          Maximum upload file size. Increase for large elections.
        '';
      };

      maxConnected = lib.mkOption {
        type = lib.types.ints.u32;
        default = 500;
        description = ''
          Number of simultaneous voters visiting the server.
        '';
      };

      # plugins = lib.mkOption {
      #   type = lib.types.listOf lib.types.path;
      #   default = [];
      #   description = ''
      #   '';
      # };
    };
  };


  ###### implementation

  config = lib.mkIf cfg.enable {
    systemd.services.belenios = {
      description = "Belenios Daemon";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/belenios-start-server";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        ExecStop = "${cfg.package}/bin/belenios-stop-server";
      };
      environment = {
        # c.f. https://gitlab.inria.fr/belenios/belenios/-/blob/master/demo/ocsigenserver-restricted.conf.in
        # BELENIOS_CONFIG="/home/kiara/Downloads/belenios/demo/ocsigenserver-restricted.conf.in";
        BELENIOS_CONFIG="${pkgs.writeText "belenios-ocsigenserver.conf.in" ''
          <!-- -*- Mode: Xml -*- -->
          <ocsigen>
            <server>
              <port>${cfg.host}:${builtins.toString cfg.port}</port>
              <mimefile>_SHAREDIR_/mime.types</mimefile>
              <logdir>_VARDIR_/log</logdir>
              <datadir>_VARDIR_/lib</datadir>
              <uploaddir>_VARDIR_/upload</uploaddir>
              <!-- increase for large elections. -->
              <maxuploadfilesize>${cfg.maxUploadFileSize}</maxuploadfilesize>
              <!-- number of simultaneous voters visiting the server. -->
              <maxconnected>${builtins.toString cfg.maxConnected}</maxconnected>
              <commandpipe>_RUNDIR_/ocsigenserver_command</commandpipe>
              <charset>utf-8</charset>
              <findlib path="_LIBDIR_"/>
              <extension name="staticmod"/>
              <extension name="redirectmod"/>
              <extension name="ocsipersist">
                <database file="_VARDIR_/lib/ocsidb"/>
              </extension>
              <extension name="eliom"/>
              <host charset="utf-8" hostfilter="*" defaulthostname="localhost">
                <!-- <redirect suburl="^$" dest="http://${cfg.domain}"/> -->
                <site path="static" charset="utf-8">
                  <static dir="_SHAREDIR_/static" cache="0"/>
                </site>
                <eliom name="belenios">
                  <public-url prefix="http://${cfg.host}:${builtins.toString cfg.port}"/>
                  <domain name="${cfg.domain}"/>
                  <!--
                    The following can be adjusted to the capacity of your system.
                    If <maxrequestbodysizeinmemory> is too small, large elections
                    might fail, in particular with so-called alternative questions
                    with many voters.
                    <maxmailsatonce> depends heavily on how sending emails is
                    handled by your system.
                  -->
                  <maxrequestbodysizeinmemory value="1048576"/>
                  <maxmailsatonce value="1000"/>
                  <tos uri="http://${cfg.domain}/terms-of-service.html"/>
                  <!-- <contact uri="mailto:contact@example.org"/> -->
                  <server mail="noreply@example.org" return-path="bounces@example.org" name="Belenios public server"/>
                  <auth-export name="email"><email/></auth-export>
                  <auth name="local"><password db="local_passwords"/></auth>
                  <source file="${cfg.package}/share/belenios.tar.gz"/>
                  <logo file="_SHAREDIR_/static/placeholder.png" mime-type="image/png"/>
                  <favicon file="_VARDIR_/favicon.ico" mime-type="image/png"/>
                  <sealing file="demo/sealing.txt" mime-type="text/plain"/>
                  <default-group group="Ed25519"/>
                  <nh-group group="Ed25519"/>
                  <share dir="_SHAREDIR_"/>
                  <storage backend="filesystem">
                    <uuid length="14"/>
                    <spool dir="_VARDIR_/spool"/>
                    <accounts dir="_VARDIR_/accounts"/>
                    <map from="local_passwords" to="demo/password_db.csv"/>
                  </storage>
                  <admin-home file="_VARDIR_/admin-home.html"/>
                  <success-snippet file="_VARDIR_/success-snippet.html"/>
                  <warning file="_VARDIR_/warning.html"/>
                  <footer file="_VARDIR_/footer.html"/>
                  ${if cfg.denyRevote then "<deny-revote/>" else ""}
                  ${if cfg.restrictedMode then "<restricted/>" else ""}
                </eliom>
              </host>
            </server>
          </ocsigen>
        ''}";
        # BELENIOS_VARDIR="$XDG_STATE_HOME/belenios";
        BELENIOS_VARDIR="\${BELENIOS_VARDIR:-\${XDG_STATE_HOME:-$HOME/.local/state}/belenios}";
        BELENIOS_RUNDIR="$(mktemp -d -t)/belenios";
        BELENIOS_BINDIR="${cfg.package}/bin";
        BELENIOS_LIBDIR="${cfg.package}/lib";
        BELENIOS_SHAREDIR="${cfg.package}/share/belenios-server";
      };
    };
  };
}
