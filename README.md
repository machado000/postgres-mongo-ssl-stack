# Dockerized PostgreSQL + MongoDB Stack with SSL and PgAdmin Proxy

Bash script that automates the setup of a secure PostgreSQL and MongoDB stack using Docker Compose.
It configures SSL certificates with Let's Encrypt, a UFW firewall, and an NGINX reverse proxy with SSL termination and PgAdmin4.

## Features

- PostgreSQL 16 with SSL enabled and custom config.
- MongoDB 7 with TLS required and client authentication disabled.
- PgAdmin4 web interface proxied via NGINX under `/pgadmin`.
- Automatic Let's Encrypt SSL certificate issuance and renewal.
- UFW firewall configuration with common DB and web ports.
- Docker volumes for persistent storage.
- Timezone set to America/Sao_Paulo (just change it).

## Prerequisites

- Ubuntu server (or Debian-based) with `apt` package manager.
- Domain name pointing to your server.
- `.env` file with these variables:

```env
DOMAIN=your.domain.com
EMAIL=your.email@example.com

PG_ADMIN_EMAIL=pgadmin@example.com
PG_ADMIN_PASSWORD=strongpassword

PG_DB_USER=postgres_user
PG_DB_PASSWORD=strongpassword
PG_DB_NAME=postgres_db

MONGO_INITDB_ROOT_USERNAME=mongo_root
MONGO_INITDB_ROOT_PASSWORD=strongpassword
```

## Usage
1. Clone and enter the project:
```bash
git clone https://github.com/yourname/yourrepo.git
cd yourrepo
```
2. Create and edit `.env` with your values.
3. Run the script:
```bash
sudo bash setup_datastack.sh
```
4. Access PgAdmin at: `https://your.domain.com/pgadmin`

## Notes
- The script enables UFW firewall with default rules for SSH, HTTP, HTTPS, PostgreSQL (5432), and MongoDB (27017).
- Certificates are obtained using Certbot with webroot validation.
- NGINX proxies PgAdmin with proper header forwarding and SSL.
- Adjust resource limits in conf/postgresql.conf as needed.

## License
MIT License
