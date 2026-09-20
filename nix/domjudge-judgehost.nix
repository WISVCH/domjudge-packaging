{
  lib,
  stdenv,
  fetchFromGitHub,
  autoconf,
  automake,
  libcgroup,
  glibc,
  php,
  bash,
  version,
}:

# DOMjudge's judgehost half (judgedaemon, runguard, runpipe, the judging
# shell scripts), built from source instead of apt-installed into an Ubuntu
# image.
#
# Installed under /opt/domjudge, the same prefix the docker/ images use, so
# icpc-playbooks and anything else driving a judgehost keeps working. The
# derivation therefore stages that tree in $out/opt/domjudge; nix/image.nix
# copies it to the real /opt/domjudge in the image.
stdenv.mkDerivation (finalAttrs: {
  pname = "domjudge-judgehost";
  inherit version;

  src = fetchFromGitHub {
    owner = "DOMjudge";
    repo = "domjudge";
    tag = finalAttrs.version;
    hash = "sha256-K7Wb1h3sdiAMYzX6uPakv6AdpJ6oAPc840MUTETqEbA=";
  };

  nativeBuildInputs = [
    autoconf
    automake
    php
  ];

  buildInputs = [ libcgroup ];

  postPatch = ''
        patchShebangs --build bootstrap
        # Each judging bind-mounts only these subdirectories of the chroot into
        # its own working directory, so without "nix" the chroot's toolchains -
        # which are nothing but /nix/store paths - are invisible to the compile
        # and run scripts. See nix/chroot.nix.
        # runpipe is the one target linked -static, so it needs libc.a/libm.a.
        # Only this rule: a global -L into glibc.static fronts the search path
        # for the dynamic links too, leaving configure unable to run what it
        # compiles ("cannot run C compiled programs").
        substituteInPlace judge/Makefile \
          --replace-fail 'runpipe.cc $(LIBHEADERS) $(LIBSOURCES)
    	$(CXX) $(CXXFLAGS) -static' 'runpipe.cc $(LIBHEADERS) $(LIBSOURCES)
    	$(CXX) $(CXXFLAGS) -L${glibc.static}/lib -static'

        substituteInPlace judge/chroot-startstop.sh.in \
          --replace-fail 'SUBDIRMOUNTS="etc usr lib bin"' \
                         'SUBDIRMOUNTS="etc usr lib bin nix"'
  '';

  # The GitHub tag archive is a git checkout, not a release tarball, so
  # ./configure has to be generated first.
  preConfigure = ''
    make configure
  '';

  configureFlags = [
    "--prefix=/opt/domjudge"
    "--enable-judgehost-build=yes"
    "--enable-domserver-build=no"
    "--with-judgehost_chrootdir=/chroot/domjudge"
    "--with-domjudge-user=domjudge"
  ];

  makeFlags = [ "judgehost" ];

  installFlags = [ "DESTDIR=${placeholder "out"}" ];
  installTargets = [ "install-judgehost" ];

  postInstall = ''
    patchShebangs $out/opt/domjudge/judgehost/bin $out/opt/domjudge/judgehost/lib/judge
  '';

  passthru = {
    inherit bash;
    prefix = "/opt/domjudge";
    chrootdir = "/chroot/domjudge";
  };

  meta = {
    description = "DOMjudge judgehost (judgedaemon, runguard) built from source";
    homepage = "https://www.domjudge.org/";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.linux;
  };
})
