{ pkgs }:

# The language toolchains domjudge-packaging's own judgehost image is built
# with, so this repository can build and test a judgehost on its own.
#
# A contest's toolchains are not decided here: icpc-nix pins exact versions
# (its languages.nix) and passes them to lib.mkJudgehostImage, so these are
# only whatever this repository's flake.lock happens to hold.
let
  # DOMjudge's C/C++ compile commands link -static, which a plain nixpkgs gcc
  # cannot do: its wrapper only knows the shared glibc ("cannot find -lc").
  gcc = pkgs.gcc.overrideAttrs (old: {
    postFixup = (old.postFixup or "") + ''
      echo "-L${pkgs.glibc.static}/lib" >> $out/nix-support/cc-ldflags
    '';
  });
in
[
  gcc
  pkgs.jdk21
  pkgs.kotlin
  pkgs.pypy3
  pkgs.python3
]
