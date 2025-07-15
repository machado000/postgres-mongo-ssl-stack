#!/bin/bash
set -euo pipefail

if [ ! -f .env ]; then
  echo "❌ .env file not found! Please create it first."
  exit 1
fi

# === LOAD ENV Variables===
# DOMAIN, EMAIL,
# PG_ADMIN_EMAIL, PG_ADMIN_PASSWORD, PG_DB_USER, PG_DB_PASSWORD, PG_DB_NAME
# MONGO_INITDB_ROOT_USERNAME, MONGO_INITDB_ROOT_PASSWORD
set -a
source .env
set +a

# === SYSTEM SETUP ===
# apt update && apt upgrade -y
# apt install -y docker.io ufw nginx python3-certbot-nginx unzip curl
# systemctl enable docker
timedatectl set-timezone America/Sao_Paulo

# === FIREWALL ===
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw allow 5432
ufw allow 27017
ufw --force enable

# === FOLDER STRUCTURE ===
mkdir -p /opt/datastack/conf && cd /opt/datastack

# === CHECK IF VOLUMES EXIST ===
for VOLUME in pgdata pgadmin_data mongodata; do
  if ! docker volume inspect "$VOLUME" >/dev/null 2>&1; then
    docker volume create "$VOLUME"
    echo "✅ Created volume: $VOLUME"
  else
    echo "🟡 Using existing volume: $VOLUME"
  fi
done

# === DOCKER COMPOSE ===
cat <<EOF > docker-compose.yml
services:
  # PostgreSQL
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
      PGADMIN_DEFAULT_EMAIL: ${PG_ADMIN_EMAIL}
      PGADMIN_DEFAULT_PASSWORD: ${PG_ADMIN_PASSWORD}
      PGADMIN_CONFIG_FORCE_SCRIPT_NAME: '"/pgadmin"'
      PGADMIN_CONFIG_PROXY_X_PREFIX: '"/pgadmin/"'
      PGADMIN_CONFIG_ENABLE_PROXY_FIX: 'True'
    expose:
      - "80"
    volumes:
      - pgadmin_data:/var/lib/pgadmin
    depends_on:
      - pg_db

  # MongoDB
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

  # NGINX Proxy
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
    healthcheck:
      test: curl -f http://pgadmin:80/ || exit 1
      interval: 15s
      timeout: 5s
      retries: 3

volumes:
  pgdata:
    external: true
  pgadmin_data:
    external: true
  mongodata:
    external: true
EOF

# === POSTGRES CONFIG ===
cat <<EOF > conf/postgresql.conf
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

cat <<EOF > conf/pg_hba.conf
# TYPE  DATABASE        USER            ADDRESS                 METHOD
# Allow local socket connections for maintenance
local   all             all                                     trust
# Allow all external TCP connections with password auth
hostssl    all             all             0.0.0.0/0               md5
EOF

# === NGINX INITIAL CONFIG ===
cat <<EOF > conf/nginx.conf
events {}
http {
    server {
        listen 80;
        server_name ${DOMAIN};
        location /.well-known/acme-challenge/ {
            root /var/www/html;
        }
    }
}
EOF

# === CERTBOT SSL CERTIFICATE ===
mkdir -p webroot && docker compose down && docker compose up -d nginx

# Wait for nginx to respond before calling certbot
echo "⏳ Waiting for nginx to respond on port 80..."
for i in {1..30}; do
  if curl -sSf http://localhost/.well-known/acme-challenge/ 2>/dev/null; then
    echo "✅ Nginx is ready!"
    break
  fi
  sleep 1
done

docker run --rm \
  -v ./letsencrypt:/etc/letsencrypt \
  -v ./webroot:/var/www/html \
  certbot/certbot certonly \
  --webroot --webroot-path=/var/www/html \
  --email "$EMAIL" --agree-tos --no-eff-email \
  --deploy-hook "echo '✅ Certificate is valid and ready'" \
  --non-interactive \
  --reuse-key \
  --keep-until-expiring \
  -d "$DOMAIN"

# Create a single PEM file with both cert + key for MongoDB
cat ./letsencrypt/live/${DOMAIN}/fullchain.pem \
    ./letsencrypt/live/${DOMAIN}/privkey.pem \
    > ./conf/mongodb.pem

# Fix permissions for postgres and mongo to read cert files
chown 999:999 ./letsencrypt/live/${DOMAIN}/privkey.pem
chmod 600 ./letsencrypt/live/${DOMAIN}/privkey.pem
chown 999:999 ./letsencrypt/live/${DOMAIN}/chain.pem
chmod 600 ./letsencrypt/live/${DOMAIN}/chain.pem
chown 999:999 ./conf/mongodb.pem
chmod 600 ./conf/mongodb.pem

# === UPDATE NGINX TO USE SSL ===
cat <<EOF > conf/nginx.conf
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
            proxy_set_header X-Forwarded-Host \$host;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header Host \$host;
            proxy_redirect off;
        }
    }
}
EOF

# === START EVERYTHING ===
docker compose down
docker compose up -d

# === DONE ===
echo -e "\n✅ PostgreSQL + MongoDB stack ready on Docker"
echo "🔗 PG Admin:    https://${DOMAIN}/pgadmin"
