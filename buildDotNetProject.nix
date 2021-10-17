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
, gcc-unwrapped
, zlib
, tlf
, libkrb5
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
, lockFile
, configFile ? ""

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
  configArg = (if configFile == "" then "" else " --configfile ${configFile}");

  nugetPackages-unpatched = stdenv.mkDerivation {
    name = "${name}-${builtins.hashFile "sha1" lockFile}-${builtins.hashString "sha1" configArg}-nuget-pkgs-unpatched";

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
      dotnet restore -r ${target} --locked-mode --use-lock-file${configArg} --lock-file-path "${lockFile}" --no-cache --nologo --packages $out $HOME/tmp-sln
    '';
  };

  depsWithRuntime = symlinkJoin {
    name = "${name}-deps-with-runtime";
    paths = [ "${sdk}/shared" nugetPackages-unpatched ];
  };


  package = stdenv.mkDerivation (args // {
    nativeBuildInputs = nativeBuildInputs ++ [ sdk autoPatchelfHook openssl makeWrapper gcc-unwrapped.lib zlib tlf libkrb5 ];
    runtimeDependencies = runtimeDependencies ++ [ icu.out ];
    
    outputs = [ "out" "nuget" ];

    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1;
    CLR_OPENSSL_VERSION_OVERRIDE=1.1;
    DOTNET_CLI_TELEMETRY_OPTOUT=1;
    LOCALE_ARCHIVE="${glibcLocales}/lib/locale/locale-archive";
    noAuditTmpdir = true;
    preDistPhases = "rpathFix";
    autoPatchelfIgnoreMissingDeps=true;

    buildPhase = args.buildPhase or ''
      export HOME="$(mktemp -d)"
      export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${openssl.out}/lib"
      mkdir -p $nuget

      dotnet restore -r ${target} --source ${depsWithRuntime} --nologo --locked-mode${configArg}  --use-lock-file --lock-file-path "${lockFile}" ${project}

      autoPatchelf $HOME

      dotnet publish --nologo --self-contained \
        -c Release -r ${target} -o out \
        --source ${depsWithRuntime} \
        --no-restore ${project}
        
      ln -s $PWD/bin/Release/net5.0/${target}/* $PWD/bin/Release/net5.0 || true
        
      dotnet pack --no-build --no-restore -o $nuget --configuration Release --nologo --runtime ${target} ${project}
      
      autoPatchelf $nuget
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