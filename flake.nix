{
  description = "Language toolchains for the DOMjudge judgehost chroot, pinned to match icpc-nix's contestant image";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages = {
          gcc = pkgs.gcc;
          openjdk21 = pkgs.jdk21;
          pypy3 = pkgs.pypy3;
          kotlin = pkgs.kotlin;
          ghc = pkgs.ghc;
          fpc = pkgs.fpc;
        };
      });
}
