#!/usr/bin/env bash
set -euo pipefail

# Simple wrapper to run the step scripts in sequence.
# Keeps each step small and debuggable; exits on first failure.

if [ ! -f .env ]; then
  echo "❌ .env file not found — create it before running this script."
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Run as root or with sudo"
  exit 1
fi

# Load environment variables for informational messages (do not fail if empty)
set -a
if [ -f .env ]; then
  # shellcheck disable=SC1091
  source .env || true
fi
set +a

echo "Running steps in sequence: 01 -> 02 -> 03 -> 04 -> 05"

STEP_DIR="$(pwd)/steps"
for s in 01 02 03 04 05; do
  script="$STEP_DIR/${s}-$(printf "%s" "" | sed -n "1p")"
  # find matching file by prefix
  file="$(ls "$STEP_DIR" | grep "^${s}-" | head -n1 || true)"
  if [ -z "$file" ]; then
    echo "⚠️ Step $s missing in $STEP_DIR — skipping"
    continue
  fi
  echo ""
  echo "--- Running step: $file ---"
  echo ""
  bash "$STEP_DIR/$file"
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "❌ Step $file failed (exit $rc). Aborting."
    exit $rc
  fi
done

echo ""
echo "✅ All steps completed successfully."
echo "Your datastack should now be deployed and running. Check containers with: docker ps"
echo ""
echo "Access pgAdmin at https://$DOMAIN/pgadmin with email: $EMAIL and password: pgadmin_password from .env"
echo ""
echo "Access Mongo Express at https://$DOMAIN/mongoexpress with username: mongo_user and password: mongo_password from .env"
echo ""