#!/usr/bin/env bash
set -euo pipefail

# Undeploy datastack:
# - Run backup_volumes.sh
# - Stop and remove containers
# - Remove named volumes
# - Remove /opt/datastack and cert files
# - Undo UFW rules (ports 80,443,5432,27017)

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Run this script as root or with sudo"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo ""
echo "WARNING: This will permanently remove containers, volumes, and /opt/datastack."
echo ""

cd "$REPO_DIR"

# Support non-interactive runs
FORCE=""
if [ "${1:-}" = "--yes" ] || [ "${1:-}" = "-y" ]; then
  FORCE=1
fi

# 1) Stop and remove compose stack (if compose file exists)
if [ -n "$FORCE" ]; then
  STOP_ANS=y
else
  read -p "Stop and remove compose stack (docker-compose.yml) and known containers? (y/N) " STOP_ANS
  STOP_ANS=${STOP_ANS:-n}
fi

if [[ "${STOP_ANS,,}" = "y" || "${STOP_ANS,,}" = "yes" ]]; then
  if [ -f /opt/datastack/docker-compose.yml ]; then
    echo "Stopping docker compose stack at /opt/datastack/docker-compose.yml..."
    docker compose -f /opt/datastack/docker-compose.yml down --volumes --remove-orphans || true
    rm -f /opt/datastack/docker-compose.yml
  else
    echo "No compose file at /opt/datastack/docker-compose.yml — attempting to remove known containers"
  fi

  # 2) Force remove known containers (if they exist)
  for C in pg_db mongo_db nginx_proxy pgadmin; do
    if docker ps -a --format '{{.Names}}' | grep -wq "$C"; then
      echo "Removing container: $C"
      docker rm -f "$C" || true
    fi
  done
else
  echo "Skipping container/compose removal as requested."
fi

# 3) Force remove data volumes (pgdata, pgadmin_data, mongodata)
if [ -n "$FORCE" ]; then
  REMOVE_VOLUMES=y
else
  read -p "Remove data volumes (pgdata, pgadmin_data, mongodata)? (y/N) " REMOVE_VOLUMES
  REMOVE_VOLUMES=${REMOVE_VOLUMES:-n}
fi

if [[ "${REMOVE_VOLUMES,,}" = "y" || "${REMOVE_VOLUMES,,}" = "yes" ]]; then
  for V in pgdata pgadmin_data mongodata; do
    if docker volume inspect "$V" >/dev/null 2>&1; then
      echo "Removing volume: $V"
      docker volume rm -f "$V" || true
    fi
  done
else
  echo "Keeping data volumes: pgdata, pgadmin_data, mongodata"
fi

# 4) Remove /opt/datastack (certs, conf, webroot)
if [ -n "$FORCE" ]; then
  REMOVE_DATSTACK=y
else
  read -p "Clean /opt/datastack contents? files=auto-delete, dirs=ask once each (y/N) " REMOVE_DATSTACK
  REMOVE_DATSTACK=${REMOVE_DATSTACK:-n}
fi

if [[ "${REMOVE_DATSTACK,,}" = "y" || "${REMOVE_DATSTACK,,}" = "yes" ]]; then
  if [ -d /opt/datastack ]; then
    echo "Cleaning contents in /opt/datastack"

    while IFS= read -r -d '' ITEM; do
      if [ -d "$ITEM" ]; then
        if [ -n "$FORCE" ]; then
          echo "Removing directory recursively: $ITEM"
          rm -rf -- "$ITEM"
        else
          # Read from terminal explicitly; loop stdin is used by find/process-substitution.
          read -r -p "Delete folder '$ITEM' recursively? (y/N) " DIR_ANS < /dev/tty
          DIR_ANS=${DIR_ANS:-n}
          if [[ "${DIR_ANS,,}" = "y" || "${DIR_ANS,,}" = "yes" ]]; then
            rm -rf -- "$ITEM"
            echo "Deleted folder: $ITEM"
          else
            echo "Skipped folder: $ITEM"
          fi
        fi
      else
        echo "Deleting file: $ITEM"
        rm -f -- "$ITEM"
      fi
    done < <(find /opt/datastack -mindepth 1 -maxdepth 1 -print0)

    echo "Finished cleaning /opt/datastack contents"
  else
    echo "No /opt/datastack directory found; nothing to remove"
  fi
else
  echo "Keeping /opt/datastack contents"
fi

# 5) Undo UFW rules we previously added (ports 80,443,5432,27017)
if command -v ufw >/dev/null 2>&1; then
  echo ""
  echo "Reverting UFW rules for ports 80,443,5432,27017 (if present)"
  set +e
  ufw status numbered | sed -n '1,200p' >/tmp/ufw_status.$$ || true
  ufw --force delete allow 5432 || true
  ufw --force delete allow 27017 || true
  ufw --force delete allow 80 || true
  ufw --force delete allow 443 || true
  rm -f /tmp/ufw_status.$$
  set -e
else
  echo "ufw not installed; skipping UFW changes"
fi

echo "✅ Undeploy complete."
echo "You may want to inspect Docker volumes and networks: docker volume ls; docker network ls"
echo ""