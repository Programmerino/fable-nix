{
  description = "Easily build dotnet projects with Nix";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  inputs.nixpkgs.url = "github:nixos/nixpkgs";


  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem(["x86_64-linux" "aarch64-linux"]) (system:
      let pkgs = import nixpkgs {
          inherit system;
        };
      in rec {
        buildDotNetProject = pkgs.callPackage ./buildDotNetProject.nix {};
      }
    );
}