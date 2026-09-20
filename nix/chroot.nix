{
  lib,
  stdenvNoCC,
  closureInfo,
  bash,
  coreutils,
  findutils,
  gawk,
  gnugrep,
  gnused,
  toolchains,
}:

# The chroot every judging runs in: the pinned language toolchains, a shell
# and coreutils, and nothing else. No debootstrap, no apt, no Ubuntu - the
# contents are exactly one Nix closure, so a judgehost compiles a submission
# with the same derivations the contestant image ships.
#
# DOMjudge bind-mounts the subdirectories named in chroot-startstop.sh's
# SUBDIRMOUNTS (etc usr lib bin, plus the "nix" that nix/domjudge-judgehost.nix
# patches in) into each judging's own directory, so all of those must exist
# here, and every binary reachable from them must resolve inside the chroot.
#
# The closure is copied in, *and* kept as a reference, so the same store
# paths exist both here and in the image's own /nix/store.
#
# That duplication is not an oversight. DOMjudge builds an output validator
# inside the chroot but runs it outside (testcase_run.sh's compare call has
# no -r), so a validator compiled by this chroot's g++ needs its ELF
# interpreter and libstdc++ - /nix/store paths - to exist in the container
# too. With the apt image both sides were Ubuntu and shared
# /lib/x86_64-linux-gnu, so this never came up. Discarding the references
# made every judging fail with "cannot start ... No such file or directory".
#
# The copy still earns its place: it is all a judging can reach, so judged
# code never sees the judgehost's own PHP, shell and sudo.
let
  # Everything a judging can reach. bash is /bin/sh, which DOMjudge's
  # compile and run scripts are.
  rootPaths = toolchains ++ [
    bash
    coreutils
    # DOMjudge's per-language build/run scripts are shell, and several of
    # them (java's main-class detection, kotlin's) use these.
    findutils
    gawk
    gnugrep
    gnused
  ];
in
stdenvNoCC.mkDerivation {
  name = "domjudge-chroot";

  closure = closureInfo { inherit rootPaths; };

  buildCommand = ''
    mkdir -p $out/nix/store $out/bin $out/usr/bin $out/etc

    # SUBDIRMOUNTS insists these exist even when they hold nothing: the
    # dynamic loader of every binary here is a /nix/store path, so nothing
    # looks in /lib or /lib64.
    mkdir -p $out/lib $out/lib64

    echo "[..] copying the toolchain closure into the chroot"
    xargs -a $closure/store-paths cp -a --parents --target-directory=$out

    echo "[..] linking toolchain binaries onto the chroot PATH"
    # A glob rather than symlinkJoin: a package's bin/ can itself be a
    # symlink (openjdk's is bin -> lib/openjdk/bin), which symlinkJoin
    # silently skips, dropping java/javac entirely.
    for pkg in ${lib.escapeShellArgs rootPaths}; do
      for bin in "$pkg"/bin/*; do
        [ -e "$bin" ] || continue
        ln -sfn "$bin" "$out/usr/bin/$(basename "$bin")"
      done
    done

    # runguard only keeps PATH from its caller, so both of the usual
    # directories are populated rather than relying on which one a judging
    # inherits.
    ln -sfn ${bash}/bin/sh $out/bin/sh
    for bin in $out/usr/bin/*; do
      ln -sfn "$(readlink "$bin")" "$out/bin/$(basename "$bin")"
    done

    # Minimal accounts: runguard resolves the run user outside the chroot,
    # but a JVM reading /etc/passwd for a home directory should not fail.
    {
      echo "root:x:0:0:root:/root:/bin/sh"
      echo "nobody:x:65534:65534:nobody:/nonexistent:/bin/sh"
    } > $out/etc/passwd
    {
      echo "root:x:0:"
      echo "nogroup:x:65534:"
    } > $out/etc/group
  '';

  passthru = { inherit toolchains; };

  meta = {
    description = "Pure-Nix DOMjudge judging chroot";
    platforms = lib.platforms.linux;
  };
}
