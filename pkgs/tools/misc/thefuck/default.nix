{ lib, stdenv, fetchFromGitHub, buildPythonApplication
, colorama, decorator, psutil, pyte, six
, go, mock, pytestCheckHook, pytest-mock
}:

buildPythonApplication rec {
  pname = "thefuck";
  version = "3.32";

  src = fetchFromGitHub {
    owner = "thenbe";
    repo = "thefuck";
    rev = "6202d325100c51076692d998e36a293955101365";
    hash = "sha256-ZTBOK6sVHQYPmvTSLQcdnyyL+89cFGjVm8czzBC2Ecg=";
  };
  doCheck = false;

  propagatedBuildInputs = [ colorama decorator psutil pyte six ];

  nativeCheckInputs = [ go mock pytestCheckHook pytest-mock ];

  disabledTests = lib.optionals stdenv.isDarwin [
    "test_settings_defaults"
    "test_from_file"
    "test_from_env"
    "test_settings_from_args"
    "test_get_all_executables_exclude_paths"
    "test_with_blank_cache"
    "test_with_filled_cache"
    "test_when_etag_changed"
    "test_for_generic_shell"
    "test_on_first_run"
    "test_on_run_after_other_commands"
    "test_when_cant_configure_automatically"
    "test_when_already_configured"
    "test_when_successfully_configured"
  ];

  meta = with lib; {
    homepage = "https://github.com/nvbn/thefuck";
    description = "Magnificent app which corrects your previous console command";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
  };
}
