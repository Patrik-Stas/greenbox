#!/usr/bin/env bash
set -euo pipefail

# Read config
GREENBOX_CONFIG="$(dirname "$0")/.greenbox"
if [ ! -f "$GREENBOX_CONFIG" ]; then
  echo "Error: .greenbox config not found"
  exit 1
fi
NAME=$(grep '^name=' "$GREENBOX_CONFIG" | cut -d= -f2)

TARGET="${1:-prod}"

if [ "$TARGET" = "dev" ]; then
  docker build --target dev -t "greenbox-${NAME}:dev" .
else
  docker build --target prod -t "greenbox-${NAME}:latest" .
fi
