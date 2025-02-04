{
  fetchFromGitHub,
  lib,
  php,
  # versionCheckHook,
}:

php.buildComposerProject2 (finalAttrs: {
  pname = "loops-server";
  version = "0.0.0";

  src = fetchFromGitHub {
    owner = "joinloops";
    repo = "loops-server";
    # tag = "v${finalAttrs.version}";
    rev = "af0a3c31cd6f5aa2cc2231f4319b43836022bc08";
    hash = "sha256-lchuRZ93NEygv3hU9gziDegIKVZVA0kwfDMEHdPnJbM=";
  };

  composerLock = ./composer.lock;
  vendorHash = "";

  # nativeInstallCheckInputs = [ versionCheckHook ];
  # doInstallCheck = true;
  # versionCheckProgram = "${placeholder "out"}/bin/${finalAttrs.meta.mainProgram}";

  meta = {
    description = "Backend server for Loops, a short video sharing platform";
    homepage = "https://joinloops.org/";
    license = lib.licenses.agpl3Plus;
    # mainProgram = "parallel-lint";
    maintainers = lib.teams.php.members;
  };
})
