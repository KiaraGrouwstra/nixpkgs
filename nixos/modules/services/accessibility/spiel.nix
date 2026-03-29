{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.spiel;

  # Build speech-provider-piper with voices looked up from the system profile,
  # so voice packages added to environment.systemPackages are discovered at runtime.
  piperProvider = pkgs.speech-provider-piper.override {
    voicesDir = "/run/current-system/sw/share/piper/voices";
  };
in
{
  options.services.spiel = {
    enable = lib.mkEnableOption "Spiel speech synthesis framework";

    providers = {
      piper = {
        enable = lib.mkEnableOption "Piper neural TTS speech provider for Spiel";

        voices = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          example = lib.literalExpression "[ pkgs.piper-voice-en-us-amy-low ]";
          description = ''
            Piper voice packages to install system-wide. Each package must
            install its model files under
            {file}`$out/share/piper/voices/<identifier>/`, where
            {file}`<identifier>` is the name exposed to Spiel clients.
          '';
        };
      };

      espeak = {
        enable = lib.mkEnableOption "eSpeak-NG speech provider for Spiel";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # libspiel installs the org.monotonous.libspiel GSettings schema and the
    # spiel CLI tool.  Both are useful whenever the service is enabled.
    # Voice packages are merged into /run/current-system/sw/share/piper/voices/
    # by the system profile, where speech-provider-piper is compiled to look.
    environment.systemPackages = [ pkgs.libspiel ] ++ cfg.providers.piper.voices;

    services.dbus.packages =
      lib.optionals cfg.providers.piper.enable [ piperProvider ]
      ++ lib.optionals cfg.providers.espeak.enable [ pkgs.speech-provider-espeak ];
  };
}
