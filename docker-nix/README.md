# docker-nix (experimental)

A parallel build of the judgehost image where the chroot's language
toolchains come from the Nix flake at the repository root (`flake.nix`)
instead of apt packages. This exists to validate that Nix-built compilers
and interpreters work correctly once chrooted and invoked by `runguard`'s
per-run sandbox, as a step toward exact language-version parity with the
[icpc-nix](https://github.com/chipcie/icpc-nix) contestant image.

## Scope

- Only the judgehost is built here; domserver is unaffected. Use
  `docker/build.sh` for domserver.
- Only the language toolchains inside the judging chroot are Nix-built. The
  chroot's base OS still comes from `dj_make_chroot`/debootstrap/apt, as
  before. The judgehost *container* itself (outside the chroot) still
  installs its own compilers via apt, unchanged from `docker/judgehost`.
- Not wired up to `icpc-nix` yet - that's a follow-up once this is proven to
  work: `icpc-nix` importing this flake as an input with
  `inputs.domjudge-packaging.inputs.nixpkgs.follows = "nixpkgs"`, and
  `images/contestant/compilers.nix` consuming the same packages.

## Building

Run from the repository root (the build needs `flake.nix`/`flake.lock`
alongside `docker-nix/judgehost/` as build context):

```sh
./docker-nix/build.sh <domjudge-version>
```

This produces `<namespace>/judgehost-nix:<version>`, a drop-in judgehost
image whose chroot's gcc/g++, JDK 21, PyPy3, Kotlin, GHC, and Free Pascal
come from the pinned nixpkgs revision in `flake.lock`. CI builds and
publishes it to `ghcr.io/<repo>/judgehost-nix` alongside the regular
`domserver`/`judgehost` images (see `build_judgehost_nix` in
`.github/workflows/build_and_push_docker.yml`).

## How it works

`docker-nix/judgehost/chroot-and-tar.sh` still runs `dj_make_chroot` to
bootstrap the base Ubuntu chroot, but removes the compilers it installs by
default (`-r gcc,g++,make,default-jdk-headless,default-jre-headless,pypy3`)
so nothing but the Nix-built toolchains ends up on the chroot's `PATH`.
`install-nix-toolchains.sh` then builds each of the flake's language
packages (`gcc`, `openjdk21`, `pypy3`, `kotlin`, `ghc`, `fpc`) and copies
their full closures straight into the chroot's filesystem at the matching
`/nix/store/<hash>` paths, symlinking each package's `bin/` entries into
`/usr/local/bin` inside the chroot. Nix store paths are content-addressed
and self-contained (compiled binaries reference their dependencies by
absolute `/nix/store/...` path), so no Nix daemon, database, or host
bind-mount is needed inside the chroot at judge time - only the files
themselves need to be present.

The packages are merged onto the chroot's `PATH` with a plain shell glob
over each package's own `bin/`, not Nix's `symlinkJoin`: `symlinkJoin`
turned out to silently drop `openjdk`'s binaries (`java`, `javac`, ...)
because its `bin` is a symlink to `lib/openjdk/bin` rather than a plain
directory, which its directory-merge logic doesn't handle.
