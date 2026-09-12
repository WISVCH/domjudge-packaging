#!/bin/sh -eu

# Experimental judgehost-only build: the chroot's language toolchains are
# built with the Nix flake at the repo root instead of apt, to eventually
# guarantee exact version parity with icpc-nix's contestant image. domserver
# is unaffected and is not built here - use docker/build.sh for that.
#
# Run from the repository root, e.g.: ./docker-nix/build.sh 5.3.0

if [ "$#" -eq 0 ] || [ "$#" -gt 2 ]
then
	echo "Usage: $0 domjudge-version <namespace>"
	echo "	For example: $0 5.3.0"
	echo "	or: $0 5.3.0 otherNamespace"
	exit 1
fi

VERSION="$1"
NAMESPACE="${2-domjudge}"
URL=https://www.domjudge.org/releases/domjudge-${VERSION}.tar.gz
FILE=domjudge.tar.gz

echo "[..] Downloading DOMjudge version ${VERSION}..."
if ! wget --quiet "${URL}" -O ${FILE}
then
	echo "[!!] DOMjudge version ${VERSION} file not found on https://www.domjudge.org/releases"
	exit 1
fi
echo "[ok] DOMjudge version ${VERSION} downloaded as domjudge.tar.gz"; echo

echo "[..] Building Nix-based judgehost image (chroot + judgehost, with intermediate build image)..."
./docker-nix/build-judgehost.sh "${NAMESPACE}/judgehost-nix:${VERSION}"
echo "[ok] Done building Docker image ${NAMESPACE}/judgehost-nix:${VERSION}"
