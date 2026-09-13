#!/bin/bash

set -euo pipefail

if [ "$#" -ne 1 ]; then
	echo "Usage: $0 <chrootdir>"
	exit 1
fi
CHROOTDIR="$1"

echo "[..] Copying pre-built Nix toolchain closure into chroot"
# The closure was built and copied to /nix-toolchains/nix/store at image
# build time (see Dockerfile.build's nix-toolchains stage), so no Nix
# install/daemon is needed here. Nix store paths are absolute and
# content-addressed, so copying them verbatim into the chroot at the same
# /nix/store/<hash> path is enough to run them there - no daemon, database,
# or host bind-mount is needed at judge time either.
cp -a /nix-toolchains/nix "$CHROOTDIR/"

echo "[..] Linking toolchain binaries onto the chroot PATH"
mkdir -p "$CHROOTDIR/usr/local/bin"
while IFS= read -r out; do
	# A plain glob (unlike Nix's symlinkJoin tree-merge) correctly follows a
	# package's bin/ even when it's itself a symlink (e.g. openjdk's
	# bin -> lib/openjdk/bin), so nothing gets silently dropped.
	for bin in "$out"/bin/*; do
		[ -e "$bin" ] || continue
		ln -sf "$bin" "$CHROOTDIR/usr/local/bin/$(basename "$bin")"
	done
done < /nix-toolchains-outputs.txt
