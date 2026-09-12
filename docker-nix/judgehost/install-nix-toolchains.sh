#!/bin/bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
	echo "Usage: $0 <chrootdir>"
	exit 1
fi
CHROOTDIR="$1"

# Keep these as separate flake outputs (not merged into one derivation) so
# icpc-nix can later cherry-pick individual packages the same way its
# images/contestant/compilers.nix already does.
PACKAGES="gcc openjdk21 pypy3 kotlin ghc fpc"

echo "[..] Building judgehost language toolchains from the domjudge-packaging Nix flake"
OUT_PATHS=""
for pkg in $PACKAGES; do
	out=$(nix --extra-experimental-features 'nix-command flakes' build --print-out-paths --no-link "/flake#${pkg}")
	OUT_PATHS="$OUT_PATHS $out"
done

echo "[..] Copying Nix closure into chroot"
# Nix store paths are absolute and content-addressed, so copying them verbatim
# into the chroot at the same /nix/store/<hash> path is enough to run them
# there: no Nix daemon, database, or host bind-mount is needed at judge time.
# shellcheck disable=SC2086
nix-store --query --requisites $OUT_PATHS \
	| xargs cp -a --parents --target-directory="$CHROOTDIR"

echo "[..] Linking toolchain binaries onto the chroot PATH"
mkdir -p "$CHROOTDIR/usr/local/bin"
# shellcheck disable=SC2086
for out in $OUT_PATHS; do
	# A plain glob (unlike Nix's symlinkJoin tree-merge) correctly follows a
	# package's bin/ even when it's itself a symlink (e.g. openjdk's
	# bin -> lib/openjdk/bin), so nothing gets silently dropped.
	for bin in "$out"/bin/*; do
		[ -e "$bin" ] || continue
		ln -sf "$bin" "$CHROOTDIR/usr/local/bin/$(basename "$bin")"
	done
done
