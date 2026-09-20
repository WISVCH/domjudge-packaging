{
  lib,
  runCommand,
  util-linux,
  bash,
  coreutils,
  chroot,
}:

# Compiles and runs a hello world for each language inside the chroot, the
# way a judging does: only the subdirectories chroot-startstop.sh mounts are
# bind-mounted into a judging directory, and the compile/run scripts are
# executed after chrooting into that directory with nothing but PATH kept.
#
# So this fails if the chroot is missing something a submission needs, and
# equally if SUBDIRMOUNTS doesn't list everything the toolchains resolve
# through - which is the whole reason "nix" is patched into it.
#
# No root and no KVM: a user namespace (unshare -r) provides both the mounts
# and the chroot, so it runs in an ordinary Nix build and in CI.
let
  # What runguard leaves a judging with: PATH only, and /usr/bin is what the
  # chroot puts the toolchains on.
  judgingPath = "/usr/bin:/bin";

  languages = [
    {
      name = "c";
      file = "hello.c";
      source = ''
        #include <stdio.h>
        int main(void) { puts("hello c"); return 0; }
      '';
      compile = "gcc -std=gnu17 -x c -O2 -static -o program hello.c -lm";
      run = "./program";
      expect = "hello c";
    }
    {
      name = "cpp";
      file = "hello.cpp";
      source = ''
        #include <iostream>
        int main() { std::cout << "hello cpp" << std::endl; }
      '';
      compile = "g++ -std=gnu++20 -x c++ -O2 -static -o program hello.cpp -lm";
      run = "./program";
      expect = "hello cpp";
    }
    {
      name = "java";
      file = "Main.java";
      source = ''
        public class Main { public static void main(String[] a) { System.out.println("hello java"); } }
      '';
      compile = "javac -encoding UTF-8 -d . Main.java";
      run = "java -Dfile.encoding=UTF-8 Main";
      expect = "hello java";
    }
    {
      name = "kotlin";
      file = "hello.kt";
      source = ''
        fun main() { println("hello kotlin") }
      '';
      compile = "kotlinc -d . hello.kt";
      run = "kotlin HelloKt";
      expect = "hello kotlin";
    }
    {
      name = "python";
      file = "hello.py";
      source = ''
        print("hello python")
      '';
      compile = "true";
      run = "pypy3 hello.py";
      expect = "hello python";
    }
  ];

  judge = language: ''
    echo "[..] ${language.name}"
    # A directory per language, never reused: the mounts are read-only and
    # a JVM can still hold one busy afterwards, so nothing is unmounted -
    # the mount namespace is discarded when this shell exits.
    judging=judging-${language.name}
    mkdir -p "$judging/compile"
    for dir in etc usr lib bin nix; do
      mkdir -p "$judging/$dir"
      mount --bind "${chroot}/$dir" "$judging/$dir"
      mount -o remount,ro,bind "$PWD/$judging/$dir"
    done
    cp ${builtins.toFile language.file language.source} "$judging/compile/${language.file}"

    # Written line by line: an indented heredoc inside this Nix string would
    # put spaces before the shebang.
    {
      echo '#!/bin/sh'
      echo 'set -e'
      echo 'cd /compile'
      echo ${lib.escapeShellArg language.compile}
      echo ${lib.escapeShellArg language.run}
    } > "$judging/compile/run.sh"
    chmod +x "$judging/compile/run.sh"

    out=$(${coreutils}/bin/env -i PATH=${judgingPath} HOME=/compile \
      ${coreutils}/bin/chroot "$judging" /compile/run.sh)
    echo "$out"
    [ "$out" = "${language.expect}" ] || {
      echo "expected '${language.expect}', got '$out'" >&2
      exit 1
    }
  '';
in
runCommand "domjudge-chroot-check" { nativeBuildInputs = [ util-linux ]; } ''
  # One namespace for all languages: the mounts and the chroot both need it,
  # and entering it once keeps this cheap.
  unshare -r -m ${bash}/bin/bash -c ${lib.escapeShellArg (lib.concatMapStrings judge languages)} || exit 1
  touch $out
''
