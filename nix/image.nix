{
  lib,
  pkgs,
  dockerTools,
  runCommand,
  writeShellApplication,
  writeText,
  bash,
  cacert,
  coreutils,
  diffutils,
  dumb-init,
  findutils,
  gawk,
  gnugrep,
  gnused,
  gzip,
  lsof,
  nettools,
  pam,
  procps,
  shadow,
  sudo,
  tzdata,
  unzip,
  util-linux,
  zip,
  domjudge-judgehost,
  chroot,
  name ? "judgehost-nix",
  tag ? "latest",
}:

# The judgehost container image, built entirely by Nix: no Ubuntu base, no
# apt, and no debootstrap when it starts. DOMjudge still lives at
# /opt/domjudge, so anything driving a judgehost (icpc-playbooks, the
# docker-compose files here) sees the same layout as the apt image.
let
  # The chroot is referenced, never copied: /chroot/domjudge is a symlink
  # into the store, which chroot-startstop.sh follows happily. A copy would
  # put its 1.5 GB in the image twice.
  chrootLink = runCommand "judgehost-chroot-link" { } ''
    mkdir -p $out/chroot
    ln -s ${chroot} $out/chroot/domjudge
  '';

  # What judgedaemon and the judging scripts shell out to. The sudoers rules
  # below name these by their /bin path, so they have to be reachable there.
  runtimeInputs = [
    bash
    coreutils
    # DOMjudge's judging scripts shell out to all of these: create_cgroups
    # to awk, check_diff.sh to diff, compile.sh/testcase_run.sh to hostname
    # for their log file names, chroot-startstop.sh to lsof when a umount
    # fails.
    diffutils
    findutils
    gawk
    gnugrep
    gnused
    gzip
    lsof
    nettools
    procps
    shadow
    sudo
    unzip
    util-linux
    zip
  ];

  # DOMjudge judges over HTTPS, and a contest's domserver often has a
  # private CA. The apt image inherited Debian's way of adding one - drop a
  # .crt into /usr/local/share/ca-certificates and run update-ca-certificates
  # - which icpc-playbooks and icpc-nix's console test both use, so this
  # image provides the same two things rather than a Nix-only convention.
  #
  # PHP's curl (judgedaemon talks to the API through it) reads the bundle
  # through OpenSSL, which honours SSL_CERT_FILE and the path below.
  caBundle = "/etc/ssl/certs/ca-certificates.crt";

  updateCaCertificates = writeShellApplication {
    name = "update-ca-certificates";
    runtimeInputs = [ coreutils ];
    text = ''
        mkdir -p "$(dirname ${caBundle})" /usr/local/share/ca-certificates
        # Rebuilt from scratch, so removing a .crt and running this again
        # really removes it.
        cat ${cacert}/etc/ssl/certs/ca-bundle.crt > ${caBundle}

      mkdir -p /etc/pam.d
      cp ${pamSudo} /etc/pam.d/sudo
      cp ${pamSudo} /etc/pam.d/other
        for crt in /usr/local/share/ca-certificates/*.crt; do
          [ -e "$crt" ] || continue
          echo "[..] Adding $crt"
          cat "$crt" >> ${caBundle}
        done
    '';
  };

  start = writeShellApplication {
    name = "judgehost-start";
    runtimeInputs = runtimeInputs ++ [ updateCaCertificates ];
    text = builtins.readFile ./judgehost-start.sh;
  };

  # DOMjudge ships sudoers rules written against /bin/mount, /bin/cp and so
  # on (etc/sudoers-domjudge.in). Those paths exist in this image because
  # the packages above are linked into /bin, so its own file is used as-is.
  sudoers = writeText "sudoers" ''
    root ALL=(ALL:ALL) SETENV: ALL

    # judgedaemon runs under sudo, and everything it shells out to - including
    # its own `sudo -n mount`, which /etc/sudoers.d/domjudge allows by
    # /bin path - has to stay findable. sudo would otherwise replace PATH
    # with its compiled-in default, which has neither /bin nor DOMjudge's
    # own bin directory.
    Defaults secure_path="/usr/bin:/bin:/opt/domjudge/judgehost/bin"

    # PHP's curl resolves the domserver's certificate through OpenSSL, which
    # reads this; without it env_reset drops the CA bundle on the way to
    # judgedaemon and a private CA stops being trusted.
    Defaults env_keep += "SSL_CERT_FILE"

    @includedir /etc/sudoers.d
  '';
  # nixpkgs' sudo is built against PAM and aborts without a configuration
  # for its service ("unable to initialize PAM: Critical error").
  #
  # Permissive on purpose: what may be run as root is decided by
  # /etc/sudoers.d/domjudge (DOMjudge's own rules, NOPASSWD for exactly
  # runguard and the chroot mounts), not by an authentication step. The apt
  # image behaved the same way - Ubuntu's PAM stack with a NOPASSWD sudoers
  # - it just inherited its configuration from the distribution.
  pamSudo = writeText "pam-sudo" ''
    auth     sufficient ${pam}/lib/security/pam_permit.so
    account  required   ${pam}/lib/security/pam_permit.so
    session  required   ${pam}/lib/security/pam_permit.so
  '';
in
dockerTools.buildLayeredImage {
  inherit name tag;

  contents = runtimeInputs ++ [
    chrootLink
    start
    updateCaCertificates
    dumb-init
  ];

  enableFakechroot = true;
  fakeRootCommands = ''
    mkdir -p /etc/sudoers.d /usr/bin /tmp /var/log \
      /usr/local/share/ca-certificates /etc/ssl/certs
    chmod 1777 /tmp

    # Some of these paths are already symlinks into the store (sudo ships
    # its own /etc/sudoers), which cannot be written through.
    rm -f /etc/sudoers /etc/passwd /etc/group /etc/shadow /etc/localtime

    # judgedaemon refuses to run as root (judgedaemon.main.php), so it runs
    # as domjudge and reaches root through sudo for runguard and the chroot
    # mounts. domjudge-run-<id> is created at startup, once DAEMON_ID is
    # known.
    cat > /etc/passwd <<'EOF'
    root:x:0:0:root:/root:/bin/bash
    domjudge:x:1000:1000:DOMjudge:/opt/domjudge:/bin/bash
    nobody:x:65534:65534:nobody:/nonexistent:/bin/false
    EOF
    cat > /etc/group <<'EOF'
    root:x:0:
    domjudge:x:1000:
    nogroup:x:65534:
    EOF
    cat > /etc/shadow <<'EOF'
    root:!:1::::::
    domjudge:!:1::::::
    EOF
    chmod 600 /etc/shadow

    # sudo refuses to run from a world-writable or non-root-owned file, and
    # cannot be setuid inside the Nix store, so it is copied out of it.
    cp ${sudo}/bin/sudo /usr/bin/sudo
    chown 0:0 /usr/bin/sudo
    chmod 4755 /usr/bin/sudo
    cp ${sudoers} /etc/sudoers
    cp ${domjudge-judgehost}/opt/domjudge/judgehost/etc/sudoers-domjudge /etc/sudoers.d/domjudge
    chown 0:0 /etc/sudoers /etc/sudoers.d/domjudge
    chmod 440 /etc/sudoers /etc/sudoers.d/domjudge

    # /opt/domjudge is a writable copy, not a store symlink: judgedaemon
    # writes etc/restapi.secret, judgings/ and log/ underneath it. It stays
    # root-owned here and is chowned to domjudge at startup - a layer owned
    # by uid 1000 cannot be unpacked by a rootless podman without a subuid
    # range configured for it.
    mkdir -p /opt/domjudge/judgehost
    # Not cp -a: preserving the store's modes fails under proot here.
    cp -r --no-preserve=mode,ownership \
      ${domjudge-judgehost}/opt/domjudge/judgehost/. /opt/domjudge/judgehost/
    chmod -R u+w /opt/domjudge/judgehost

    ln -sfn ${tzdata}/share/zoneinfo /etc/zoneinfo
    cat ${cacert}/etc/ssl/certs/ca-bundle.crt > ${caBundle}

    mkdir -p /etc/pam.d
    cp ${pamSudo} /etc/pam.d/sudo
    cp ${pamSudo} /etc/pam.d/other

    # Everything created above belongs to root: these commands run as the
    # Nix build user, and a layer owned by another uid needs a subuid range
    # to unpack under a rootless podman.
    chown -Rh 0:0 /etc /opt /usr /tmp /var
    chmod 4755 /usr/bin/sudo
  '';

  config = {
    Entrypoint = [
      "${dumb-init}/bin/dumb-init"
      "--"
    ];
    Cmd = [ "${start}/bin/judgehost-start" ];
    Env = [
      # /usr/bin first for the setuid sudo; everything else is in /bin.
      "PATH=/usr/bin:/bin:/opt/domjudge/judgehost/bin"
      "SSL_CERT_FILE=${caBundle}"
      "CONTAINER_TIMEZONE=Europe/Amsterdam"
      "DOMSERVER_BASEURL=http://domserver/"
      "JUDGEDAEMON_USERNAME=judgehost"
      "JUDGEDAEMON_PASSWORD=password"
      "DAEMON_ID=0"
      "DOMJUDGE_CREATE_WRITABLE_TEMP_DIR=0"
      "RUN_USER_UID_GID=62860"
    ];
  };

  passthru = {
    inherit chroot domjudge-judgehost;
    toolchains = chroot.toolchains;
  };
}
