#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="/var/log/agent-app"
ARCHIVE_DIR="/var/log/monitor/agent-app/archive"

mkdir -p "$ARCHIVE_DIR"

find "$SRC_DIR" -type f -name '*.log' -mtime +7 -exec sh -c '
  archive_dir="$1"
  shift

  for file do
    gzip -c "$file" > "$archive_dir/$(basename "$file").gz"
  done
' sh "$ARCHIVE_DIR" {} +

find "$ARCHIVE_DIR" -type f -name '*.gz' -mtime +30 -delete
