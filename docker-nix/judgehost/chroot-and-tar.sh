#!/bin/bash

set -euo pipefail

# All language toolchains now come from Nix (install-nix-toolchains.sh), so
# the only apt packages needed here are whatever dj_make_chroot requires for
# a working base Ubuntu system. Remove the compilers/JDK/pypy3 it installs by
# default so nothing but the Nix-built toolchains end up on the chroot's PATH.
# Usage: https://github.com/DOMjudge/domjudge/blob/main/misc-tools/dj_make_chroot.in#L58-L87
/opt/domjudge/judgehost/bin/dj_make_chroot -R noble \
	-r gcc,g++,make,default-jdk-headless,default-jre-headless,pypy3

CHROOTDIR=$(sed -n 's/^CHROOTDIR="\(.*\)"$/\1/p' /opt/domjudge/judgehost/bin/dj_make_chroot | head -n1)
/scripts/install-nix-toolchains.sh "$CHROOTDIR"

cd /
echo "[..] Compressing chroot"
tar -czpf /chroot.tar.gz --exclude=/chroot/tmp --exclude=/chroot/proc --exclude=/chroot/sys --exclude=/chroot/mnt --exclude=/chroot/media --exclude=/chroot/dev --one-file-system /chroot
echo "[..] Compressing judge"
tar -czpf /judgehost.tar.gz /opt/domjudge/judgehost
