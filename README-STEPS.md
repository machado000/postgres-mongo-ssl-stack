Stepwise setup for datastack

Run these scripts in order, as root. Each step is minimal and has no fallbacks.

1) System preparation
  sudo bash steps/01-system.sh

2) Install Docker
  sudo bash steps/02-docker.sh

3) Start nginx compose (serves ACME webroot)
  sudo bash steps/03-compose.sh

4) Obtain Let's Encrypt certs
  sudo bash steps/04-certbot.sh

After certs are obtained you can extend the compose file to add postgres/mongo services.
