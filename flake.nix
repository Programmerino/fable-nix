{
  description = "Easily build dotnet projects with Nix";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  inputs.nixpkgs.url = "github:nixos/nixpkgs";

  inputs.fable.url = "github:Programmerino/fable.nix";

  outputs = { self, nixpkgs, flake-utils, fable }:
    flake-utils.lib.eachSystem(["x86_64-linux" "aarch64-linux" "x86_64-darwin"]) (system:
      let pkgs = import nixpkgs {
          inherit system;
        };
      in rec {
        buildDotNetProject = pkgs.callPackage ./buildDotNetProject.nix { fable = fable.defaultPackage."${system}";};
      }
    );
}
