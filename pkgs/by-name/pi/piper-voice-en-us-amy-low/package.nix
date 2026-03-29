{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  model = fetchurl {
    url = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/low/en_US-amy-low.onnx";
    hash = "sha256-pakau33g8QQ1iiWt7UgN2s8f8HYohjJYhuxAai6GqrM=";
  };
  config = fetchurl {
    url = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/low/en_US-amy-low.onnx.json";
    hash = "sha256-IlCppgW43DWhFnF/rcUFZpXdgJ40oV0C9yoPUtU9Prs=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "piper-voice-en-us-amy-low";
  version = "2.0.0";

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    dir=$out/share/piper/voices/en_US-amy-low
    mkdir -p "$dir"
    cp ${model} "$dir/en_US-amy-low.onnx"
    cp ${config} "$dir/en_US-amy-low.onnx.json"
    runHook postInstall
  '';

  meta = {
    description = "Amy (low quality) English US voice for Piper TTS";
    homepage = "https://rhasspy.github.io/piper-samples/";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jtojnar ];
    platforms = lib.platforms.all;
  };
}
