{
  stdenvNoCC,
  lib,
  symlinkJoin,
  cacert,
  makeWrapper,
  dotnetCorePackages,
  mkNugetDeps,
  mkNugetSource,
  buildDotnetModule,
  fable ? {},
}: {
  name ? "${args.pname}-${args.version}",
  pname ? name,
  fablePackage ? fable,
  projectFile ? null,
  nugetDeps ? null,
  buildType ? "Release",
  language ? "JavaScript",
  dotnet-sdk ? dotnetCorePackages.sdk_6_0,
  dotnet-runtime ? dotnetCorePackages.runtime_6_0,
  ...
} @ args:
with builtins; let
  arrayToShell = a:
    if (isString a)
    then a
    else toString (map (lib.escape (lib.stringToCharacters "\\ ';$`()|<>\t")) a);

  nugetPackages = mkNugetDeps {
    name = "${name}-nugetPackages-deps";
    nugetDeps = import nugetDeps;
  };

  nugetSource = mkNugetSource {
    name = "${name}-nugetPackages-source";
    deps = [nugetPackages];
  };

  sdkDeps = mkNugetDeps {
    name = "dotnet-sdk-${dotnet-sdk.version}-deps";
    nugetDeps = dotnet-sdk.passthru.packages;
  };

  sdkSource = mkNugetSource {
    name = "dotnet-sdk-${dotnet-sdk.version}-source";
    deps = [sdkDeps];
  };

  depsWithRuntime = symlinkJoin {
    name = "${name}-nuget-source";
    paths = [nugetSource sdkSource];
  };

  package = stdenvNoCC.mkDerivation (args
    // {
      inherit name;
      passthru.fetch-deps =
        (buildDotnetModule {
          pname = name;
          src = args.src;
          version = args.version;
        })
        .passthru
        .fetch-deps;
      # inherit version;

      nativeBuildInputs = [cacert dotnet-sdk makeWrapper];

      configurePhase = ''
        runHook preConfigure


        dotnetRestore() {
          local -r project="''${1-}"
          dotnet restore ''${project} \
            -p:ContinuousIntegrationBuild=true \
            -p:Deterministic=true \
            --source "${depsWithRuntime}/lib"
        }

        (( "''${#projectFile[@]}" == 0 )) && dotnetRestore

        for project in ${arrayToShell projectFile}; do
            dotnetRestore "$project"
        done

        runHook postConfigure
      '';

      dontStrip = true;
      dontInstall = true;
      dontWrapGApps = true;

      buildPhase = ''
        runHook preBuild

        dotnetBuild() {
          local -r project="''${1-}"
          ${fablePackage}/bin/fable --configuration ${buildType} --noRestore --optimize --lang "${language}" ''${project} -o "$out/lib/${pname}"
        }

        (( "''${#projectFile[@]}" == 0 )) && dotnetBuild

        for project in ${arrayToShell projectFile}; do
            dotnetBuild "$project"
        done

        runHook postBuild
      '';
    });
in
  package
