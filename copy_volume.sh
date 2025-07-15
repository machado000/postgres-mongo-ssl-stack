#!/bin/bash

echo "Enter source volume name (from):"
read FROM_VOL

echo "Enter destination volume name (to):"
read TO_VOL

# Check if FROM volume exists
if ! docker volume inspect "$FROM_VOL" >/dev/null 2>&1; then
  echo "❌ Volume '$FROM_VOL' does not exist."
  exit 1
fi

# Check if TO volume exists
if docker volume inspect "$TO_VOL" >/dev/null 2>&1; then
  echo "⚠️ Volume '$TO_VOL' already exists. Do you want to erase its contents? [y/N]"
  read CONFIRM
  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    docker run --rm -v "$TO_VOL":/to alpine sh -c "rm -rf /to/*"
  else
    echo "❌ Aborted by user."
    exit 1
  fi
else
  docker volume create "$TO_VOL"
fi

# Copy data
echo "📦 Copying data from '$FROM_VOL' to '$TO_VOL'..."
docker run --rm \
  -v "$FROM_VOL":/from \
  -v "$TO_VOL":/to \
  alpine sh -c "cd /from && cp -a . /to"

# Compare volumes
echo "🔍 Comparing volumes..."
docker run --rm \
  -v "$FROM_VOL":/vol1 \
  -v "$TO_VOL":/vol2 \
  alpine sh -c "cd /vol1 && find . | sort > /tmp/a && cd /vol2 && find . | sort > /tmp/b && diff /tmp/a /tmp/b" \
  && echo "✅ Volumes appear identical." \
  || echo "⚠️ Volumes differ in structure."
