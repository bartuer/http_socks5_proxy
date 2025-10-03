#!/usr/bin/env bash
# Install packages required for the HTTP→SOCKS proxy stack.
set -euo pipefail

sudo apt-get update

sudo apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  lsb-release

DIST_ID=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
DIST_CODENAME=$(lsb_release -cs)

case "${DIST_ID}" in
  ubuntu)
    OPENRESTY_REPO="http://openresty.org/package/ubuntu"
    ;;
  debian)
    OPENRESTY_REPO="http://openresty.org/package/debian"
    ;;
  *)
    echo "Unsupported distribution: ${DIST_ID}" >&2
    exit 1
    ;;
esac

KEYRING_PATH=/usr/share/keyrings/openresty-archive-keyring.gpg
LIST_PATH=/etc/apt/sources.list.d/openresty.list

if [ ! -f "${KEYRING_PATH}" ]; then
  curl -fsSL https://openresty.org/package/pubkey.gpg \
    | sudo gpg --dearmor -o "${KEYRING_PATH}"
fi

echo "deb [signed-by=${KEYRING_PATH}] ${OPENRESTY_REPO} ${DIST_CODENAME} main" \
  | sudo tee "${LIST_PATH}" >/dev/null

sudo apt-get update

sudo apt-get install -y \
  openresty \
  privoxy \
  pandoc \
  lua-cjson \
  curl
