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

cd /opt/datastack

# Reuse existing certs when already present for this domain.
USE_EXISTING_CERTS=0
if [ -d "/opt/datastack/letsencrypt" ] && \
   [ -f "./letsencrypt/live/${DOMAIN}/privkey.pem" ] && \
   [ -f "./letsencrypt/live/${DOMAIN}/fullchain.pem" ] && \
   [ -f "./letsencrypt/live/${DOMAIN}/chain.pem" ]; then
  read -r -p "Existing Let's Encrypt certificates found for ${DOMAIN}. Reuse them? (Y/n) " REUSE_CERTS
  REUSE_CERTS=${REUSE_CERTS:-Y}
  if [ "${REUSE_CERTS,,}" != "n" ]; then
    echo "✅ Reusing existing certificates in ./letsencrypt/live/${DOMAIN}"
    USE_EXISTING_CERTS=1
  fi
fi

if [ "$USE_EXISTING_CERTS" -ne 1 ]; then
  # sanity check: local webroot response (retry briefly for nginx startup)
  echo "sanity: checking local webroot via http://localhost"
  OK=0
  for i in $(seq 1 30); do
    if curl -fsS --max-time 5 http://localhost/.well-known/acme-challenge/test.txt >/dev/null; then
      echo "✅ local nginx serving webroot"
      OK=1
      break
    fi
    echo "waiting for nginx... ($i/30)"
    sleep 1
  done
  if [ "$OK" -ne 1 ]; then
    echo "❌ local nginx not serving webroot after retries"
    exit 1
  fi

  # sanity check: public DNS resolves to this host
  PUBLIC_IP=$(curl -fsS https://api.ipify.org) || PUBLIC_IP=""
  echo "public ip: $PUBLIC_IP"

  echo "sanity: checking http://$DOMAIN/.well-known/acme-challenge/test.txt"
  if ! curl -fsS --max-time 8 http://$DOMAIN/.well-known/acme-challenge/test.txt >/dev/null; then
    echo "⚠️ $DOMAIN did not respond to HTTP check from this host — this may still succeed from the internet."
    echo "If your DNS points to this host but the check fails, verify provider firewall or NAT loopback rules."
    read -p "Proceed to certbot anyway? (y/N) " ans
    if [ "${ans,,}" != "y" ]; then
      echo "aborting"
      exit 1
    fi
  fi

  docker run --rm -v $(pwd)/letsencrypt:/etc/letsencrypt -v $(pwd)/webroot:/var/www/html certbot/certbot certonly \
    --webroot --webroot-path=/var/www/html --email "$EMAIL" --agree-tos --no-eff-email --non-interactive -d "$DOMAIN"

  echo "certbot: done (check /opt/datastack/letsencrypt)"
fi

# Ensure conf directory exists
mkdir -p ./conf

# Backup and avoid directory collisions for conf/mongodb.pem
TS=$(date -u +%Y%m%dT%H%M%SZ)
if [ -d ./conf/mongodb.pem ]; then
  mv ./conf/mongodb.pem ./conf/mongodb.pem.dir.bak-$TS
  echo "⚠️ ./conf/mongodb.pem was a directory — moved to ./conf/mongodb.pem.dir.bak-$TS"
fi
if [ -f ./conf/mongodb.pem ]; then
  mv ./conf/mongodb.pem ./conf/mongodb.pem.bak-$TS
  echo "⚠️ Existing ./conf/mongodb.pem moved to ./conf/mongodb.pem.bak-$TS"
fi

# Ensure expected cert files exist
if [ ! -f ./letsencrypt/live/${DOMAIN}/privkey.pem ] || [ ! -f ./letsencrypt/live/${DOMAIN}/fullchain.pem ] || [ ! -f ./letsencrypt/live/${DOMAIN}/chain.pem ]; then
  echo "❌ Expected certificate files not found in ./letsencrypt/live/${DOMAIN}."
  exit 1
fi

# Create combined PEM for MongoDB (cert + key)
cat ./letsencrypt/live/${DOMAIN}/fullchain.pem ./letsencrypt/live/${DOMAIN}/privkey.pem > ./conf/mongodb.pem
chmod 600 ./conf/mongodb.pem || true

# Harden letsencrypt files and set ownership when possible
chmod 600 ./letsencrypt/live/${DOMAIN}/privkey.pem || true
chmod 644 ./letsencrypt/live/${DOMAIN}/fullchain.pem ./letsencrypt/live/${DOMAIN}/chain.pem || true

# Ensure numeric UID 999 ownership so containers (common DB UID) can read files
chown 999:999 ./conf/mongodb.pem ./letsencrypt/live/${DOMAIN}/privkey.pem ./letsencrypt/live/${DOMAIN}/chain.pem || true
# also set live and archive dir ownership so mounts and real key files are readable inside containers
chown -R 999:999 ./letsencrypt/live/${DOMAIN} ./letsencrypt/archive/${DOMAIN} || true

echo "✅ Created ./conf/mongodb.pem and adjusted permissions"
