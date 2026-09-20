#!/usr/bin/env bash

# Container entrypoint for the Nix-built judgehost image: the same steps the
# apt image's docker/judgehost/scripts/start.sh takes, without the
# Debian-only bits (no dpkg-reconfigure, no /etc/resolv.conf copy - judged
# code has no network).

set -euo pipefail

# A _FILE variant wins over the plain variable, so a password can come from
# a mounted secret rather than the environment.
file_or_env() {
	local file="${1}_FILE"
	if [ -n "${!file:-}" ]; then
		cat "${!file}"
	else
		echo -n "${!1:-}"
	fi
}

echo "[..] Setting timezone to ${CONTAINER_TIMEZONE}"
ln -snf "/etc/zoneinfo/${CONTAINER_TIMEZONE}" /etc/localtime
echo "${CONTAINER_TIMEZONE}" >/etc/timezone

cd /opt/domjudge/judgehost

# The image ships this tree root-owned (see nix/image.nix), so judgedaemon's
# own user gets it here, where it is writable.
echo "[..] Taking ownership of /opt/domjudge/judgehost"
chown -R domjudge: /opt/domjudge/judgehost

echo "[..] Setting up restapi file"
judgedaemon_password="$(file_or_env JUDGEDAEMON_PASSWORD)"
printf 'default\t%sapi/v4\t%s\t%s\n' \
	"${DOMSERVER_BASEURL}" "${JUDGEDAEMON_USERNAME}" "${judgedaemon_password}" \
	>etc/restapi.secret
chown domjudge: etc/restapi.secret
chmod 600 etc/restapi.secret

echo "[..] Setting up cgroups"
bin/create_cgroups

if ! id "domjudge-run-${DAEMON_ID}" >/dev/null 2>&1; then
	echo "[..] Creating run user domjudge-run-${DAEMON_ID}"
	groupadd -f -g "${RUN_USER_UID_GID}" domjudge-run
	useradd -u "${RUN_USER_UID_GID}" -N -d /nonexistent -g nogroup -s /bin/false \
		"domjudge-run-${DAEMON_ID}"
fi

echo "[ok] Starting judgedaemon ${DAEMON_ID}"
exec sudo -u domjudge \
	DOMJUDGE_CREATE_WRITABLE_TEMP_DIR="${DOMJUDGE_CREATE_WRITABLE_TEMP_DIR}" \
	/opt/domjudge/judgehost/bin/judgedaemon -n "${DAEMON_ID}"
