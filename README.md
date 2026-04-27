# Dockerized PostgreSQL + MongoDB Stack with SSL and PgAdmin Proxy

Step-based Bash scripts to deploy a secure PostgreSQL + MongoDB stack with Docker Compose.
The stack uses Let's Encrypt certificates, UFW firewall rules, and NGINX SSL termination with pgAdmin4 behind `/pgadmin`.

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
2. Create and edit `.env` with your values (you can copy from `.env.example`).
3. Deploy using the step runner:
```bash
sudo bash deploy_datastack.sh
```
4. Access pgAdmin at `https://your.domain.com/pgadmin`

## Step Scripts

You can run each step independently for easier troubleshooting:

```bash
sudo bash steps/01-system.sh
sudo bash steps/02-docker.sh
sudo bash steps/03-compose.sh
sudo bash steps/04-certbot.sh
sudo bash steps/05-deploy.sh
```

## Undeploy

Use the undeploy script to remove the stack safely:

```bash
sudo bash undeploy_datastack.sh
```

Non-interactive mode:

```bash
sudo bash undeploy_datastack.sh --yes
```

## Notes
- UFW rules are applied for SSH, HTTP, HTTPS, PostgreSQL (5432), and MongoDB (27017).
- Certificates are obtained using Certbot webroot validation.
- `steps/04-certbot.sh` can reuse existing valid Let's Encrypt certificates for the configured domain.
- NGINX proxies pgAdmin with forwarded headers and cookie path rewrite for `/pgadmin`.
- If pgAdmin login fails after proxy/path changes, clear browser cookies for the domain.
- Adjust resource limits in `conf/postgresql.conf` as needed.

## License
MIT License
