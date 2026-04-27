#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Run as root"
  exit 1
fi

cd /opt/datastack

cat > docker-compose.yml <<'EOF'
services:
  nginx:
    image: nginx:alpine
    container_name: nginx_proxy
    ports:
      - '80:80'
      - '443:443'
    volumes:
      - ./conf/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./webroot:/var/www/html:ro
    restart: always
EOF

cat > conf/nginx.conf <<'EOF'
events {}
http {
  server {
    listen 80;
    server_name _;
    location /.well-known/acme-challenge/ {
      root /var/www/html;
    }
    location / {
      return 200 'ok';
    }
  }
}
EOF

mkdir -p webroot/.well-known/acme-challenge
echo "test-$(date +%s)" > webroot/.well-known/acme-challenge/test.txt

docker compose -f docker-compose.yml up -d

echo "compose: ok (nginx started)"
