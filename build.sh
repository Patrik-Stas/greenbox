#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-prod}"

if [ "$TARGET" = "dev" ]; then
  docker build --target dev -t greenbox:dev .
else
  docker build --target prod -t greenbox .
fi
