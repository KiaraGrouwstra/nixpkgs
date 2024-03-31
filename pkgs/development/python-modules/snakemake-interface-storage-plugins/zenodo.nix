{ lib
, buildPythonPackage
, fetchFromGitHub
, poetry-core
, requests
, snakemake-interface-common
, snakemake-interface-storage-plugins
, snakemake
}:

buildPythonPackage rec {
  pname = "snakemake-storage-plugin-zenodo";
  version = "0.1.2";
  format = "pyproject";

  src = fetchFromGitHub {
    owner = "snakemake";
    repo = pname;
    rev = "refs/tags/v${version}";
    hash = "sha256-8n98iuHz0jJXY1b+f5o2nYMgokZ0gO3udEgQ5+b4Kk8=";
  };

  nativeBuildInputs = [
    poetry-core
  ];

  propagatedBuildInputs = [
    requests
    snakemake
    snakemake-interface-common
    snakemake-interface-storage-plugins
  ];

  pythonImportsCheck = [ "snakemake_storage_plugin_zenodo" ];

  meta = with lib; {
    description = "A Snakemake storage plugin for reading from and writing to zenodo.org";
    homepage = "https://github.com/snakemake/snakemake-storage-plugin-zenodo";
    license = licenses.mit;
    maintainers = with maintainers; [ veprbl ];
  };
}
