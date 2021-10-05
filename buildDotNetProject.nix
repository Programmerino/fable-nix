{ stdenv
, stdenvNoCC
, lib
, symlinkJoin
, runCommand
, curl
, cacert
, unzip
, icu
, openssl
, jq
, autoPatchelfHook
, patchelf
, glibcLocales
, makeWrapper
}:

{ name ? "${args'.pname}-${args'.version}"
, version
, buildInputs ? []
, nativeBuildInputs ? []
, runtimeDependencies ? []
, passthru ? {}
, patches ? []
, meta ? {}
, project ? ""

, binaryFiles ? [name]
, sdk
, system
, nugetHostList ? [ "https://api.nuget.org/v3-flatcontainer/" ]
, nugetSha256

, ...}@args':

with builtins;

let
  args = removeAttrs args' [
    "binaryPath"
    "sdk"
    "system"
    "nugetHostList"
    "nugetSha256"
  ];

  cases = { "x86_64-linux" = "linux-x64"; "aarch64-linux" = "linux-arm64";};

  target = cases."${system}";
  arrayToShell = (a: toString (map (lib.escape (lib.stringToCharacters "\\ ';$`()|<>\t") ) a));

  nugetPackages-unpatched = stdenv.mkDerivation {
    name = "${name}-nuget-pkgs-unpatched";

    outputHashAlgo = "sha256";
    outputHash = nugetSha256;
    outputHashMode = "recursive";

    nativeBuildInputs = [ sdk curl cacert unzip ];

    dontFetch = true;
    dontUnpack = true;
    dontStrip = true;
    dontConfigure = true;
    dontPatch = true;
    dontBuild = true;
    DOTNET_CLI_TELEMETRY_OPTOUT=1;

    installPhase = ''
      set -e
      mkdir -p $out
      export HOME=$(mktemp -d)
      cp -R ${args.src} $HOME/tmp-sln
      chmod -R +rw $HOME/tmp-sln
      dotnet restore -r ${target} --locked-mode --no-cache --packages $out $HOME/tmp-sln
    '';
  };

  depsWithRuntime = symlinkJoin {
    name = "${name}-deps-with-runtime";
    paths = [ "${sdk}/shared" nugetPackages-unpatched ];
  };


  package = stdenv.mkDerivation (args // {
    nativeBuildInputs = nativeBuildInputs ++ [ sdk autoPatchelfHook openssl makeWrapper ];
    runtimeDependencies = runtimeDependencies ++ [ icu.out ];

    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1;
    CLR_OPENSSL_VERSION_OVERRIDE=1.1;
    DOTNET_CLI_TELEMETRY_OPTOUT=1;
    LOCALE_ARCHIVE="${glibcLocales}/lib/locale/locale-archive";
    noAuditTmpdir = true;
    preDistPhases = "rpathFix";

    buildPhase = args.buildPhase or ''
      export HOME="$(mktemp -d)"
      export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${openssl.out}/lib"

      dotnet restore -r ${target} --source ${depsWithRuntime} --nologo

      autoPatchelf $HOME

      dotnet publish ${project} --nologo --self-contained \
        -c Release -r ${target} -o out \
        --source ${depsWithRuntime} \
        --no-restore
    '';

    installPhase = args.installPhase or ''
      runHook preInstall
      mkdir -p $out/bin
      cp -r ./out/* $out
      cd $out
      for binaryPattern in ${arrayToShell binaryFiles} ''${binaryFilesArray[@]}
      do
          for bin in ./$binaryPattern
          do
            [ -f "$bin" ] || continue
            ln -s $out/$bin $out/bin/$bin
          done
      done
      runHook postInstall
    '';

      rpathFix = ''
        cd $out
        find . ! -name '*.dll' ! -name '*.so' ! -name '*.xml' ! -name '*.a' -type f -executable -print0 | while read -d $'\0' file
        do
          if output=$(patchelf --print-rpath $file 2>/dev/null); then
              wrapProgram "$out/$file" --prefix LD_LIBRARY_PATH : "$output"
          else
            echo $file was not a valid ELF file
          fi
        done

      '';

  });
in package
