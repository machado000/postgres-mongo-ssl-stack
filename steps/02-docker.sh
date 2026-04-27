#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Run as root"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y ca-certificates gnupg lsb-release curl

install -m0755 -d /etc/apt/keyrings
# write keyring to a temp file and atomically replace to avoid interactive prompts
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg.tmp
mv -f /etc/apt/keyrings/docker.gpg.tmp /etc/apt/keyrings/docker.gpg
chmod 0644 /etc/apt/keyrings/docker.gpg || true
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

docker --version
docker compose version

echo "docker: ok"
