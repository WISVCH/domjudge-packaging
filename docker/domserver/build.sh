#!/bin/sh -eu

# Use venv to use latest Sphinx. 6.1.0 or higher is required to build DOMjudge docs.
. /venv/bin/activate

cd /domjudge-src/domjudge*
chown -R domjudge: .
# If we used a local source tarball, it might not have been built yet
sudo -u domjudge make dist
sudo -u domjudge ./configure --with-baseurl=http://dj.chipcie.ch.tudelft.nl/ --disable-judgehost-build --with-install-method=docker

# Passwords should not be included in the built image. We create empty files here to prevent passwords from being generated.
sudo -u domjudge touch etc/dbpasswords.secret etc/restapi.secret etc/symfony_app.secret etc/initial_admin_password.secret

sudo -u domjudge make domserver docs
make install-domserver install-docs

# Remove installed password files
rm /opt/domjudge/domserver/etc/*.secret
