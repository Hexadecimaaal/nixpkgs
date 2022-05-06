{ lib, stdenv, fetchFromGitHub, rustPlatform, makeWrapper, callPackage
, nodePackages, cmake, nodejs, unzip, python3, pkg-config, libsecret
}:
assert lib.versionAtLeast python3.version "3.5";
let
  publisher = "vadimcn";
  pname = "vscode-lldb";
  version = "1.7.0";

  vscodeExtUniqueId = "${publisher}.${pname}";

  src = fetchFromGitHub {
    owner = "vadimcn";
    repo = "vscode-lldb";
    rev = "v${version}";
    sha256 = "sha256-1d9Yf6cnJBb5RyhQ24sQylWyzNDlSkyBkvd+S0ioQBA=";
  };

  lldb = callPackage ./lldb.nix {};

  adapter = rustPlatform.buildRustPackage {
    pname = "${pname}-adapter";
    inherit version src;

    # It will pollute the build environment of `buildRustPackage`.
    cargoPatches = [ ./reset-cargo-config.patch ];

    cargoSha256 = "sha256-GUPeFIGc6ZdXhmUq66t/k0rhWHWijv6hRMWJ6ih1W+U=";

    nativeBuildInputs = [ makeWrapper ];

    buildAndTestSubdir = "adapter";

    buildFeatures = [ "weak-linkage" ];

    cargoBuildFlags = [
      "--lib"
      "--bin=codelldb"
    ];

    # Tests are linked to liblldb but it is not available here.
    doCheck = false;
  };

  nodeDeps = nodePackages
    ."vscode-lldb-build-deps-../../applications/editors/vscode/extensions/vscode-lldb/build-deps"
    .override {
      nativeBuildInputs = [ pkg-config libsecret ];
    };

in stdenv.mkDerivation {
  pname = "vscode-extension-${publisher}-${pname}";
  inherit src version vscodeExtUniqueId;

  installPrefix = "share/vscode/extensions/${vscodeExtUniqueId}";

  nativeBuildInputs = [ cmake nodejs unzip makeWrapper ];

  patches = [ ./cmake-build-extension-only.patch ./cmake-vsce-echo-y.patch ];

  postConfigure = ''
    cp -r ${nodeDeps}/lib/node_modules/vscode-lldb/{node_modules,package-lock.json} .
  '';

  cmakeFlags = [
    # Do not append timestamp to version.
    "-DVERSION_SUFFIX="
  ];
  makeFlags = [ "vsix_bootstrap" ];

  installPhase = ''
    ext=$out/$installPrefix
    runHook preInstall

    unzip ./codelldb-bootstrap.vsix 'extension/*' -d ./vsix-extracted

    mkdir -p $ext/{adapter,formatters}
    mv -t $ext vsix-extracted/extension/*
    cp -t $ext/adapter ${adapter}/{bin,lib}/* ../adapter/*.py
    wrapProgram $ext/adapter/codelldb \
      --set-default LLDB_DEBUGSERVER_PATH "${lldb.out}/bin/lldb-server"
    cp -t $ext/formatters ../formatters/*.py
    ln -s ${lldb.lib} $ext/lldb
    # Mark that all components are installed.
    touch $ext/platform.ok

    runHook postInstall
  '';

  # `adapter` will find python binary and libraries at runtime.
  postFixup = ''
    wrapProgram $out/$installPrefix/adapter/codelldb \
      --prefix PATH : "${python3}/bin" \
      --prefix LD_LIBRARY_PATH : "${python3}/lib"
  '';

  passthru = {
    inherit lldb adapter;
  };

  meta = with lib; {
    description = "A native debugger extension for VSCode based on LLDB";
    homepage = "https://github.com/vadimcn/vscode-lldb";
    license = with licenses; [ mit ];
    maintainers = with maintainers; [ nigelgbanks ];
    platforms = platforms.all;
  };
}
