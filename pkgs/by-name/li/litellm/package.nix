{ configFiles, python3Packages }:

let
  litellm = python3Packages.litellm;
in
python3Packages.toPythonApplication (
  litellm.overridePythonAttrs (oldAttrs: {
    dependencies =
      (oldAttrs.dependencies or [ ])
      ++ litellm.optional-dependencies.proxy
      ++ litellm.optional-dependencies.extra_proxy
      ++ litellm.optional-dependencies.proxy-runtime;

    passthru = (oldAttrs.passthru or { }) // {
      config = configFiles {
        name = "litellm";
        relativeTo = "the directory that holds the configuration of LiteLLM";
        modules = [ ./config-module.nix ];
      };
    };
  })
)
