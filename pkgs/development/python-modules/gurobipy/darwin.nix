{ fetchurl, python, xar, cpio, cctools, insert_dylib }:
assert python.pkgs.isPy27 && python.ucsEncoding == 2;
python.pkgs.buildPythonPackage
  { pname = "gurobipy";
    version = "11.0.1";
    src = fetchurl
      { url = "http://packages.gurobi.com/11.0/gurobi11.0.1_mac64.pkg";
        sha256 = "";
      };
    buildInputs = [ xar cpio cctools insert_dylib ];
    unpackPhase =
      ''
        xar -xf $src
        zcat gurobi*mac64tar.pkg/Payload | cpio -i
        tar xf gurobi*_mac64.tar.gz
        sourceRoot=$(echo gurobi*/*64)
        runHook postUnpack
      '';
    patches = [ ./no-clever-setup.patch ];
    postInstall = "mv lib/lib*.so $out/lib";
    postFixup =
      ''
        install_name_tool -change \
          /System/Library/Frameworks/Python.framework/Versions/2.7/Python \
          ${python}/lib/libpython2.7.dylib \
          $out/lib/python2.7/site-packages/gurobipy/gurobipy.so
        install_name_tool -change /Library/gurobi1101/mac64/lib/libgurobi75.so \
          $out/lib/libgurobi75.so \
          $out/lib/python2.7/site-packages/gurobipy/gurobipy.so
        insert_dylib --inplace $out/lib/libaes75.so \
          $out/lib/python2.7/site-packages/gurobipy/gurobipy.so
      '';
  }
