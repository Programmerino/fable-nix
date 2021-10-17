# dotnet-nix
Based heavily on the work of [\@Elyhaka](https://gist.github.com/Elyhaka/0f0e3afe488100487ada6a2a8bef78a4), and retrofitted to work as a flake and to work with problematic libraries that need patchelf and ICU support.

*I'm new to Nix and flakes, so feel free to tell me if something is off*

## Usage

This is edited from one of my projects where I use the library:
```nix

{
  description = "Demo usage";

  inputs.nixpkgs.url = "github:nixos/nixpkgs";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  inputs.dotnet.url = "github:Programmerino/dotnet-nix";

  outputs = { self, nixpkgs, flake-utils, dotnet }:
    flake-utils.lib.eachSystem(["x86_64-linux" "aarch64-linux"]) (system:
      let
        pkgs = import nixpkgs { 
          inherit system;
        };
        name = "demoApp";
        version = "0.0.0";
        sdk = pkgs.dotnetCorePackages.sdk_5_0;

      in rec {
          devShell = pkgs.mkShell {
            DOTNET_CLI_HOME = "/tmp/dotnet_cli";
            buildInputs = defaultPackage.nativeBuildInputs ++ [sdk];
            DOTNET_ROOT = "${sdk}";
          };
    
          defaultPackage = dotnet.buildDotNetProject.${system} rec {
              inherit name;
              inherit version;
              inherit sdk;
              inherit system;
              src = ./.;
              lockFile = ./packages.lock.json;
              configFile = ./nuget.config; # optional

              nugetSha256 = "sha256-cDAIZvRGVS+QoTub+XWAT9OwRaodMXSMFEJaIkJ2lHQ=";
              binaryFiles = [ "myBinaryFileName" ]; # name of project is included by default
          };
      }
    );
}
```

In order to use this, you must run ```dotnet restore -f --use-lock-file --force-evaluate``` to generate the lock file necessary for deterministic builds whenever you change dependencies for you project (and the first time). Depending on the projects you reference, you may need ```dotnet restore -r {RUNTIMEID} -f --use-lock-file --force-evaluate```. Whenever your Nuget config is changed or the lock file changes, you will need to replace ```nugetSha256``` with the hash specified while running ```nix build```.

If you want to keep versioning and naming consistent with the project, you can use this in your `csproj`, `fsproj`, etc.:
```xml
<PackageId Condition="'$(name)' != ''">$(name)</PackageId>
<Version Condition="'$(version)' != ''">$(version)</Version>
```