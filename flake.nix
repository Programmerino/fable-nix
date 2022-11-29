{
  description = "Easily build Fable projects with Nix";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  inputs.nixpkgs.url = "github:nixos/nixpkgs";

  inputs.dotnet-tools.url = "github:Programmerino/dotnet-tools.nix";

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    dotnet-tools,
  }:
    flake-utils.lib.eachSystem ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"] (
      system: let
        pkgs = import nixpkgs {
          inherit system;
        };
      in rec {
        buildFableProject = pkgs.callPackage ./buildFableProject.nix {fable = dotnet-tools.packages."${system}".fable;};
      }
    );
}
