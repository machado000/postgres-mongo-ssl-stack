#!/bin/bash
set -euo pipefail

BACKUP_DIR="./backups"
DATE=$(date +%Y%m%d_%H%M)
mkdir -p "$BACKUP_DIR"

# Filter out volumes with hex-only names (usually 64 hex chars)
VOLUMES=$(docker volume ls --format '{{.Name}}' | grep -vE '^[0-9a-f]{64}$')

for VOLUME in $VOLUMES; do
  BACKUP_FILE="${BACKUP_DIR}/${VOLUME}_${DATE}.tar.gz"
  echo "📦 Backing up volume: $VOLUME -> $BACKUP_FILE"
  docker run --rm \
    -v "${VOLUME}:/volume" \
    -v "$(pwd)/${BACKUP_DIR}:/backup" \
    alpine \
    sh -c "tar czf /backup/$(basename "$BACKUP_FILE") -C /volume ."
done

echo -e "\n✅ Backup complete. Files created:"
ls -lh "$BACKUP_DIR"/*.tar.gz
