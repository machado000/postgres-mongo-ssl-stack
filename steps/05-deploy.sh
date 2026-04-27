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

echo "Preparing TLS files and compose from letsencrypt for domain: $DOMAIN"

if [ ! -d "./letsencrypt/live/$DOMAIN" ]; then
  echo "❌ Letsencrypt certificates not found at ./letsencrypt/live/$DOMAIN"
  echo "Run steps/04-certbot.sh first to obtain certificates." 
  exit 1
fi

if [ ! -f "./letsencrypt/live/${DOMAIN}/privkey.pem" ] || [ ! -f "./letsencrypt/live/${DOMAIN}/fullchain.pem" ] || [ ! -f "./letsencrypt/live/${DOMAIN}/chain.pem" ]; then
  echo "❌ Missing certificate files in ./letsencrypt/live/${DOMAIN}"
  echo "Expected: privkey.pem, fullchain.pem and chain.pem"
  exit 1
fi

mkdir -p conf

# Create mongodb.pem (fullchain + privkey)
TS=$(date -u +%Y%m%dT%H%M%SZ)
# Protect against accidental directory at conf/mongodb.pem
if [ -d ./conf/mongodb.pem ]; then
  mv ./conf/mongodb.pem ./conf/mongodb.pem.dir.bak-$TS
  echo "⚠️ ./conf/mongodb.pem was a directory — moved to ./conf/mongodb.pem.dir.bak-$TS"
fi
if [ -f ./conf/mongodb.pem ]; then
  mv ./conf/mongodb.pem ./conf/mongodb.pem.bak-$TS
  echo "⚠️ Existing ./conf/mongodb.pem moved to ./conf/mongodb.pem.bak-$TS"
fi

cat ./letsencrypt/live/${DOMAIN}/fullchain.pem ./letsencrypt/live/${DOMAIN}/privkey.pem > ./conf/mongodb.pem
chmod 600 ./conf/mongodb.pem || true

# Copy server cert/key for Postgres
cp ./letsencrypt/live/${DOMAIN}/fullchain.pem ./conf/server.crt
cp ./letsencrypt/live/${DOMAIN}/privkey.pem ./conf/server.key
chmod 600 ./conf/server.key || true

# Harden letsencrypt files and created server key
chmod 600 ./letsencrypt/live/${DOMAIN}/privkey.pem || true
chmod 644 ./letsencrypt/live/${DOMAIN}/fullchain.pem ./letsencrypt/live/${DOMAIN}/chain.pem || true

# Ensure numeric UID 999 ownership so container DB users can read mounted TLS files
chown 999:999 ./letsencrypt/live/${DOMAIN}/privkey.pem ./letsencrypt/live/${DOMAIN}/chain.pem ./conf/mongodb.pem ./conf/server.key ./conf/server.crt || true
chown -R 999:999 ./letsencrypt/live/${DOMAIN} ./letsencrypt/archive/${DOMAIN} || true

# Ensure volumes exist (these are external in the compose)
for V in pgdata pgadmin_data mongodata; do
  if ! docker volume inspect "$V" >/dev/null 2>&1; then
    docker volume create "$V"
    echo "✅ Created volume: $V"
  else
    echo "🟡 Using existing volume: $V"
  fi
done

echo "Writing docker-compose.yml (full stack)"
cat > docker-compose.yml <<EOF
services:
  pg_db:
    image: postgres:16
    container_name: pg_db
    restart: always
    environment:
      POSTGRES_USER: ${PG_DB_USER}
      POSTGRES_PASSWORD: ${PG_DB_PASSWORD}
      POSTGRES_DB: ${PG_DB_NAME}
      TZ: America/Sao_Paulo
      LANG: en_US.UTF-8
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./conf/postgresql.conf:/etc/postgresql/postgresql.conf
      - ./conf/pg_hba.conf:/etc/postgresql/pg_hba.conf
      - ./letsencrypt/live/${DOMAIN}/fullchain.pem:/etc/ssl/certs/server.crt:ro
      - ./letsencrypt/live/${DOMAIN}/privkey.pem:/etc/ssl/private/server.key:ro
    command: ["postgres",
              "-c", "config_file=/etc/postgresql/postgresql.conf",
              "-c", "hba_file=/etc/postgresql/pg_hba.conf"]

  pgadmin:
    image: dpage/pgadmin4
    container_name: pgadmin
    restart: always
    environment:
      - PGADMIN_DEFAULT_EMAIL=${PG_ADMIN_EMAIL}
      - PGADMIN_DEFAULT_PASSWORD=${PG_ADMIN_PASSWORD}
      - PGADMIN_CONFIG_FORCE_SCRIPT_NAME='/pgadmin'
      - PGADMIN_CONFIG_PROXY_X_PREFIX='/pgadmin/'
      - PGADMIN_CONFIG_ENABLE_PROXY_FIX=True
    expose:
      - "80"
    volumes:
      - pgadmin_data:/var/lib/pgadmin
    depends_on:
      - pg_db

  mongo_db:
    image: mongo:7
    restart: always
    container_name: mongo_db
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_INITDB_ROOT_USERNAME}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_INITDB_ROOT_PASSWORD}
      TZ: America/Sao_Paulo
    ports:
      - "27017:27017"
    volumes:
      - mongodata:/data/db
      - ./conf/mongodb.pem:/etc/ssl/mongodb.pem:ro
      - ./letsencrypt/live/${DOMAIN}/chain.pem:/etc/ssl/ca.pem:ro
    command: [
      "mongod",
      "--tlsMode", "requireTLS",
      "--tlsCertificateKeyFile", "/etc/ssl/mongodb.pem",
      "--tlsCAFile", "/etc/ssl/ca.pem",
      "--tlsAllowConnectionsWithoutCertificates",
      "--auth"
    ]

  nginx:
    image: nginx:alpine
    container_name: nginx_proxy
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./conf/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./letsencrypt:/etc/letsencrypt:ro
      - ./webroot:/var/www/html:ro
    depends_on:
      - pgadmin

volumes:
  pgdata:
    external: true
  pgadmin_data:
    external: true
  mongodata:
    external: true
EOF

# Write DB and nginx configs if missing (safe to overwrite with same content)
cat > conf/postgresql.conf <<EOF
shared_buffers = 256MB
work_mem = 4MB
maintenance_work_mem = 64MB
effective_cache_size = 768MB
max_connections = 20
log_min_duration_statement = 500
listen_addresses = '*'
ssl = on
ssl_cert_file = '/etc/ssl/certs/server.crt'
ssl_key_file = '/etc/ssl/private/server.key'
EOF

cat > conf/pg_hba.conf <<EOF
# TYPE  DATABASE        USER            ADDRESS                 METHOD
# Allow local socket connections for maintenance
local   all             all                                     trust
# Allow all external TCP connections with password auth
hostssl    all             all             0.0.0.0/0               md5
EOF

cat > conf/nginx.conf <<EOF
events {}
http {
    server {
        listen 80;
        server_name ${DOMAIN};
        return 301 https://\$host\$request_uri;
    }

    server {
        listen 443 ssl;
        server_name ${DOMAIN};

        ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

        location / {
            return 404;
        }

        location /pgadmin/ {
          proxy_pass http://pgadmin:80/;
          proxy_set_header X-Script-Name /pgadmin;
          proxy_set_header X-Forwarded-Prefix /pgadmin;
          proxy_set_header X-Forwarded-Host \$host;
          proxy_set_header X-Forwarded-Proto \$scheme;
          proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
          proxy_set_header Host \$host;
          proxy_redirect off;
          # Ensure cookies set by pgAdmin are scoped to the /pgadmin path
          proxy_cookie_path / /pgadmin/;
        }
    }
}
EOF

echo "Bringing down any existing compose stack and starting full stack"
docker compose down || true
docker compose up -d

echo ""
echo "pgAdmin server registration hint:"
echo "  Host name/address: pg_db"
echo "  Port: 5432"
echo "  Maintenance DB: ${PG_DB_NAME}"
echo "  Username: ${PG_DB_USER}"
echo "  Password: (value from PG_DB_PASSWORD in .env)"

echo "Deployment requested. Check running containers with: docker ps --filter name=pg_db --filter name=mongo_db --filter name=nginx_proxy --filter name=pgadmin"
echo "Done."
