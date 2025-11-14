{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  python3,
}:

buildNpmPackage rec {
  pname = "haraka-plugin-ldap";
  version = "1.1.3";

  src = fetchFromGitHub {
    owner = "haraka";
    repo = "haraka-plugin-ldap";
    tag = "v${version}";
    hash = "sha256-9x+SzeWzKYr0M7r56ljHD2EQLtwjvQ8yCLTyH566mRc=";
  };

  npmDepsHash = "sha256-Yqo/1tm66HvgZKSrLGwt8HPCHOR6ir4/HNqCgkkzzCo=";

  dontNpmBuild = true;

  nativeBuildInputs = [
    python3
  ];

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  meta = {
    changelog = "https://github.com/haraka/haraka-plugin-ldap/blob/${src.tag}/CHANGELOG.md";
    description = "Developing LDAP plugins for Haraka";
    homepage = "https://haraka.github.io/plugins/auth/auth_ldap/";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ kiara ];
  };
}
