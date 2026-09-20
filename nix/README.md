# Nix-built judgehost

A judgehost container image built entirely by Nix: no Ubuntu base, no apt,
and no `dj_make_chroot`/debootstrap when the container starts. The judging
chroot is one Nix closure, so the compilers a submission is judged with can
be *the same derivations* a contestant machine ships.

That is the point. icpc-nix builds contestant images from pinned nixpkgs
revisions, while the apt judgehost got its toolchains from Ubuntu, so the
two could drift apart silently - wrong Java version, a language that behaves
differently under judging than on the contestant's desk. See
[icpc-nix#61](https://github.com/WISVCH/icpc-nix/issues/61) and
[icpc-nix#74](https://github.com/WISVCH/icpc-nix/issues/74).

## What's here

| file | what it is |
|---|---|
| `domjudge.json` | The DOMjudge version both images are built from. CI reads it with `jq`, Nix reads it in `flake.nix`. |
| `domjudge-judgehost.nix` | DOMjudge's judgehost half (judgedaemon, runguard, runpipe) built from source, installed at `/opt/domjudge`. |
| `chroot.nix` | The judging chroot: the toolchain closure, `/bin/sh`, coreutils, and nothing else. |
| `image.nix` | The container image: `dockerTools.buildLayeredImage`, a setuid `sudo`, DOMjudge's own sudoers rules. |
| `judgehost-start.sh` | The entrypoint: restapi secret, cgroups, run user, then judgedaemon. |
| `toolchains.nix` | The toolchains *this repository* builds with. A contest's versions come from the caller. |
| `check-chroot.nix` | Compiles and runs a hello world per language inside the chroot, the way a judging does. |
| `domserver-image.json` | The domserver image CI last pushed, by digest. Written by CI. |

## Use it from another flake

```nix
inputs.domjudge-packaging.url = "github:WISVCH/domjudge-packaging";

# Your toolchains, your nixpkgs - the image is built around them.
image = inputs.domjudge-packaging.lib.mkJudgehostImage {
  inherit pkgs;
  toolchains = [ myGcc myJdk myKotlin myPypy ];
};
```

`lib.judgehostFor` returns the same thing in pieces (`image`, `chroot`,
`domjudge-judgehost`, `check`), for a caller that wants to assert something
about the chroot - for example that its toolchain store paths are exactly
the ones its contestant image installs.

`inputs.domjudge-packaging.images.x86_64-linux.domserver` is the domserver
image that CI built from the same `domjudge.json` version, so one input
bump moves both halves.

## Two things worth knowing

**`SUBDIRMOUNTS` is patched.** DOMjudge bind-mounts only `etc usr lib bin`
(plus `lib64`) of the chroot into each judging. Every binary here is a
`/nix/store` path, so `domjudge-judgehost.nix` patches `nix` into that list
in `judge/chroot-startstop.sh.in`. Without it a judging sees the symlinks in
`/usr/bin` and nothing they point at. This is worth proposing upstream as a
configurable list.

**The chroot's closure is copied, with references discarded.** `chroot.nix`
copies the closure to its own `nix/store` and sets `unsafeDiscardReferences`,
so the image carries the toolchains once rather than twice. The copy is
self-contained: everything it needs is beneath it.

## Testing

`nix flake check` compiles and runs C, C++, Java, Kotlin and Python inside
the chroot. It mounts exactly what `chroot-startstop.sh` mounts and keeps
only `PATH`, like runguard, so it fails if the chroot is missing something
or if `SUBDIRMOUNTS` is wrong. A user namespace gives it the mounts and the
chroot, so it needs neither root nor KVM.

What it does *not* cover is a real judging: judgedaemon talking to a
domserver, cgroups, runguard's sandbox. That needs root and a domserver, and
lives in icpc-nix's console VM test.

A rootless podman cannot run this image: judgedaemon runs as `domjudge`
(uid 1000), which a rootless container has no mapping for unless subuid
ranges are configured.
