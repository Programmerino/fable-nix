{
  stdenv,
  lib,
  symlinkJoin,
  cacert,
  makeWrapper,
  nodejs,
  fable ? {},
}: {
  name ? "${args'.pname}-${args'.version}",
  version,
  fablePackage ? fable,
  nodePackage ? nodejs,
  buildInputs ? [],
  nativeBuildInputs ? [],
  runtimeDependencies ? [],
  passthru ? {},
  patches ? [],
  meta ? {},
  project ? "",
  lockFile,
  configFile ? "",
  binaryFiles ? [name],
  language ? "JavaScript",
  sdk,
  system,
  nugetSha256,
  ...
} @ args':
with builtins; let
  args = removeAttrs args' [
    "binaryPath"
    "sdk"
    "system"
    "nugetHostList"
    "nugetSha256"
  ];
  arrayToShell = a: toString (map (lib.escape (lib.stringToCharacters "\\ ';$`()|<>\t")) a);
  configArg =
    if configFile == ""
    then ""
    else " --configfile ${configFile}";

  nugetPackages-unpatched = stdenv.mkDerivation {
    name = "${name}-nugetPackages-unpatched";

    outputHashAlgo = "sha256";
    outputHash = nugetSha256;
    outputHashMode = "recursive";

    nativeBuildInputs = [sdk cacert];

    dontFetch = true;
    dontUnpack = true;
    dontStrip = true;
    dontConfigure = true;
    dontPatch = true;

    __noChroot =
      if stdenv.isDarwin
      then true
      else false;

    dontBuild = true;
    DOTNET_CLI_TELEMETRY_OPTOUT = 1;
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = 1;
    NUGET_CERT_REVOCATION_MODE = "offline";

    installPhase = ''
      mkdir -p $out
      export HOME=$(mktemp -d)
      cp -R ${args.src} $HOME/tmp-sln
      chmod -R +rw $HOME/tmp-sln
      cd $HOME/tmp-sln
      dotnet restore ${project} --locked-mode --use-lock-file${configArg} --lock-file-path "${lockFile}" --no-cache --packages $out --nologo
    '';
  };

  depsWithRuntime = symlinkJoin {
    __noChroot =
      if stdenv.isDarwin
      then true
      else false;
    name = "${name}-deps-with-runtime";
    paths = ["${sdk}/shared" nugetPackages-unpatched];
  };

  package = stdenv.mkDerivation (args
    // {
      inherit name;
      inherit version;

      nativeBuildInputs = nativeBuildInputs ++ [sdk makeWrapper];
      DOTNET_CLI_TELEMETRY_OPTOUT = 1;
      DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = 1;
      dontFixup = true;
      dontConfigure = true;
      __noChroot =
        if stdenv.isDarwin
        then true
        else false;
      buildPhase =
        args.buildPhase
        or ''
          runHook preBuild

          export HOME=$(mktemp -d)
          mkdir -p $out
          dotnet restore --source ${depsWithRuntime} --nologo --locked-mode${configArg}  --use-lock-file --lock-file-path "${lockFile}" ${project}
          ${fablePackage}/bin/fable precompile --lang ${language} ${project} -o $out
          runHook postBuild
        '';

      installPhase =
        args.installPhase
        or ''
          runHook preInstall
          mkdir -p $out/bin
          cd $out
          for binaryPattern in ${arrayToShell binaryFiles} ''${binaryFilesArray[@]}
          do
              for bin in ./$binaryPattern
              do
                [ -f "$bin" ] || continue
                chmod +x $bin
                sed -i '1 i #!${nodePackage}/bin/node' $bin
                ln -s $out/$bin $out/bin/$(basename $bin .js)
              done
          done
          runHook postInstall
        '';
    });
in
  package
