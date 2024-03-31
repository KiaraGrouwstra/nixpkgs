{ lib
, buildPythonPackage
, fetchFromGitHub
, poetry-core
, requests
, requests-oauthlib
, snakemake-interface-common
, snakemake-interface-storage-plugins
, snakemake
}:

buildPythonPackage rec {
  pname = "snakemake-storage-plugin-http";
  version = "0.2.3";
  format = "pyproject";

  src = fetchFromGitHub {
    owner = "snakemake";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-tckWSFy0Y/B7FR7zjASAENcDKg5zy2T9xvQiP+4O0Sc=";
  };

  nativeBuildInputs = [
    poetry-core
  ];

  propagatedBuildInputs = [
    requests
    requests-oauthlib
    snakemake
    snakemake-interface-common
    snakemake-interface-storage-plugins
  ];

  pythonImportsCheck = [ "snakemake_storage_plugin_http" ];

  meta = with lib; {
    description = "Snakemake storage plugin for downloading input files from HTTP(s).";
    homepage = "https://github.com/snakemake/snakemake-storage-plugin-http";
    license = licenses.mit;
    maintainers = with maintainers; [ veprbl ];
  };
}
