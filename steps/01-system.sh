#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Run as root"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ ! -f "$REPO_DIR/.env" ]; then
  echo "❌ $REPO_DIR/.env not found"
  exit 1
fi
set -a
source "$REPO_DIR/.env"
set +a

if [ -z "${DOMAIN:-}" ] || [ -z "${EMAIL:-}" ]; then
  echo "❌ DOMAIN or EMAIL missing in $REPO_DIR/.env"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y ufw curl nginx

# Allow SSH and HTTP(S) only for now
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw allow 27017
ufw allow 5432
ufw --force enable

mkdir -p /opt/datastack/webroot /opt/datastack/conf
chown -R root:root /opt/datastack

echo "system: ok"
echo "Created /opt/datastack with webroot and conf."
