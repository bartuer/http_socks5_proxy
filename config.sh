#!/usr/bin/env bash

set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
	echo "error: this script must be run as root" >&2
	exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"
NGINX_CONF_DEFAULT="${REPO_ROOT}/root/usr/local/openresty/nginx/conf/nginx.conf"
NGINX_CONF="${NGINX_CONF:-${NGINX_CONF_DEFAULT}}"
SERVICE_UNIT_DEFAULT="${REPO_ROOT}/root/systemd/system/azuresshproxy.service"
SERVICE_UNIT="${SERVICE_UNIT:-${SERVICE_UNIT_DEFAULT}}"

if [[ ! -f "${NGINX_CONF}" ]]; then
	echo "error: nginx config not found at ${NGINX_CONF}" >&2
	exit 1
fi

if [[ ! -f "${SERVICE_UNIT}" ]]; then
	echo "error: azuresshproxy service file not found at ${SERVICE_UNIT}" >&2
	exit 1
fi

CURRENT_USER="$(id -un)"

if [[ -z "${CURRENT_USER}" ]]; then
	echo "error: unable to detect current user" >&2
	exit 1
fi

USER_HOME="$(getent passwd "${CURRENT_USER}" | cut -d: -f6)"
if [[ -z "${USER_HOME}" ]]; then
	USER_HOME="$(eval echo "~${CURRENT_USER}")"
fi

if [[ -z "${USER_HOME}" || ! -d "${USER_HOME}" ]]; then
	echo "error: could not resolve home directory for ${CURRENT_USER}" >&2
	exit 1
fi

if ! WINDOWS_HOSTNAME_RAW=$(/mnt/c/Windows/System32/cmd.exe /c hostname 2>/dev/null); then
	echo "error: failed to read Windows hostname via cmd.exe" >&2
	exit 1
fi

# Strip trailing carriage returns and newlines produced by cmd.exe
WINDOWS_HOSTNAME="$(echo "${WINDOWS_HOSTNAME_RAW}" | tr -d '\r\n')"

if [[ -z "${WINDOWS_HOSTNAME}" ]]; then
	echo "error: Windows hostname resolved to an empty string" >&2
	exit 1
fi

STATIC_ROOT="${REPO_ROOT}/static"

if [[ ! -d "${STATIC_ROOT}" ]]; then
	echo "error: static directory missing at ${STATIC_ROOT}" >&2
	exit 1
fi

README_EN="${STATIC_ROOT}/README.md"
README_ZH="${STATIC_ROOT}/README.zh.md"
PAC_FILE="${STATIC_ROOT}/proxy-google-youtube-gemini.pac"
INSTALL_GUIDE="${REPO_ROOT}/INSTALL.md"
DOCS_HOSTNAME="${WINDOWS_HOSTNAME}.local"
DOCS_URL="http://${DOCS_HOSTNAME}"

for doc in "${README_EN}" "${README_ZH}" "${PAC_FILE}" "${INSTALL_GUIDE}"; do
	if [[ ! -f "${doc}" ]]; then
		echo "error: expected file missing: ${doc}" >&2
		exit 1
	fi
done

# Replace only the first occurrence of server_name and root directives
sed -i \
	-e "0,/^user[[:space:]]\+[^;]*;/s#^user[[:space:]]\+[^;]*;#user ${CURRENT_USER};#" \
	-e "0,/server_name[[:space:]]\+[^;]*;/s#server_name[[:space:]]\+[^;]*;#server_name ${DOCS_HOSTNAME};#" \
	-e "0,/root[[:space:]]\+[^;]*;/s#root[[:space:]]\+[^;]*;#root ${STATIC_ROOT};#" \
	"${NGINX_CONF}"

echo "Updated ${NGINX_CONF}:" >&2
echo "  user        -> ${CURRENT_USER}" >&2
echo "  server_name -> ${DOCS_HOSTNAME}" >&2
echo "  root        -> ${STATIC_ROOT}" >&2

# Update systemd service file with current user context
sed -i \
	-e "s#^User=.*#User=${CURRENT_USER}#" \
	-e "s#^Environment=HOME=.*#Environment=HOME=${USER_HOME}#" \
	-e "s#^WorkingDirectory=.*#WorkingDirectory=${USER_HOME}#" \
	"${SERVICE_UNIT}"

echo "Updated ${SERVICE_UNIT}:" >&2
echo "  User              -> ${CURRENT_USER}" >&2
echo "  Environment HOME  -> ${USER_HOME}" >&2
echo "  WorkingDirectory  -> ${USER_HOME}" >&2

# Update documentation and PAC references to use the Windows hostname with .local
for file in "${README_EN}" "${README_ZH}" "${PAC_FILE}"; do
	sed -E -i \
		-e "s#play\.local#${DOCS_HOSTNAME}#g" \
		-e "s#hostname\\.local#${DOCS_HOSTNAME}#g" \
		-e "s#http://${WINDOWS_HOSTNAME}(\\.local)?#${DOCS_URL}#g" \
		-e "s#${WINDOWS_HOSTNAME}(\\.local)?#${DOCS_HOSTNAME}#g" \
		"${file}"
	echo "Updated ${file}:" >&2
	echo "  hostname -> ${DOCS_HOSTNAME}" >&2
done

sed -E -i \
	-e "s#\[http://${WINDOWS_HOSTNAME}(\\.local)?\]\(http://${WINDOWS_HOSTNAME}(\\.local)?\)#[http://${DOCS_HOSTNAME}](http://${DOCS_HOSTNAME})#g" \
	-e "s#http://${WINDOWS_HOSTNAME}(\\.local)?#${DOCS_URL}#g" \
	-e "s#\[http://hostname\\.local\]\(http://hostname\\.local\)#[http://${DOCS_HOSTNAME}](http://${DOCS_HOSTNAME})#g" \
	-e "s#http://hostname\\.local#${DOCS_URL}#g" \
	"${INSTALL_GUIDE}"

echo "Updated ${INSTALL_GUIDE}:" >&2
echo "  hostname -> ${DOCS_URL}" >&2

# Package configuration and deploy to system locations (mirroring pack.config.txt)
ARCHIVE_PATH="${REPO_ROOT}/proxy.config.tar.gz"
pushd "${REPO_ROOT}/root" >/dev/null
tar -czf "${ARCHIVE_PATH}" .
popd >/dev/null
echo "Created archive ${ARCHIVE_PATH}" >&2

tar -zxf "${ARCHIVE_PATH}" -C /
echo "Extracted configuration archive to /" >&2

SYSTEMD_TARGET_DIR="/etc/systemd/system"
SYSTEMD_UNIT_NAME="$(basename "${SERVICE_UNIT}")"
SYSTEMD_TARGET_PATH="${SYSTEMD_TARGET_DIR}/${SYSTEMD_UNIT_NAME}"
install -D -m 0644 "${SERVICE_UNIT}" "${SYSTEMD_TARGET_PATH}"
echo "Installed ${SERVICE_UNIT} -> ${SYSTEMD_TARGET_PATH}" >&2

# Validate OpenResty and Privoxy configurations
if openresty -t; then
	echo "openresty -t succeeded" >&2
else
	echo "error: openresty -t failed" >&2
	exit 1
fi

if privoxy --config-test /etc/privoxy/config; then
	echo "privoxy --config-test succeeded" >&2
else
	echo "error: privoxy --config-test failed" >&2
	exit 1
fi

# Apply systemd changes and start services
systemctl daemon-reload

services=(openresty privoxy azuresshproxy)
for svc in "${services[@]}"; do
	systemctl enable "${svc}" >/dev/null 2>&1 || true
	if ! systemctl restart "${svc}"; then
		echo "error: failed to restart ${svc}" >&2
		systemctl --no-pager --lines=20 status "${svc}" >&2 || true
		exit 1
	fi
	status="$(systemctl is-active "${svc}" 2>/dev/null || true)"
	echo "Service ${svc}: ${status}" >&2
	if [[ "${status}" != "active" ]]; then
		echo "error: ${svc} is not active" >&2
		systemctl --no-pager --lines=20 status "${svc}" >&2 || true
		exit 1
	fi
	systemctl --no-pager --lines=5 status "${svc}" >&2 || true
done

# Report listening ports
echo "Listening sockets (filtered):" >&2

print_ports_table() {
	local pattern=':(80|8080|8081)$'

	if command -v netstat >/dev/null 2>&1; then
		netstat -ltnp 2>/dev/null | awk -v pattern="${pattern}" '
			BEGIN {
				header = sprintf("%-6s %-24s %-24s %s", "Proto", "Local Address", "Foreign Address", "PID/Program")
				printed = 0
			}
			NR <= 2 { next }
			$4 ~ pattern {
				if (!printed) {
					print header
					printed = 1
				}
				printf "%-6s %-24s %-24s %s\n", $1, $4, $5, $7
			}
			END {
				if (!printed) {
					exit 1
				}
			}
		'
	else
		ss -H -ltnp 2>/dev/null | awk -v pattern="${pattern}" '
			BEGIN {
				header = sprintf("%-6s %-24s %-24s %s", "Proto", "Local Address", "Peer Address", "Process")
				printed = 0
			}
			$4 ~ pattern {
				if (!printed) {
					print header
					printed = 1
				}
				proc = ""
				idx = index($0, "users:")
				if (idx > 0) {
					proc = substr($0, idx)
				}
				printf "%-6s %-24s %-24s %s\n", $1, $4, $5, proc
			}
			END {
				if (!printed) {
					exit 1
				}
			}
		'
	fi
}

if ! print_ports_table >&2; then
	echo "  (no matches)" >&2
fi
