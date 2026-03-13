#!/usr/bin/env bash
set -euo pipefail

DIR="$HOME/.claude_mine"
FILE="$DIR/.credentials.json"

mkdir -p "$DIR"
chmod 700 "$DIR"

if [ ! -f "$FILE" ]; then
  touch "$FILE"
  chmod 600 "$FILE"
  echo "Created $FILE — paste your credentials into it."
else
  chmod 600 "$FILE"
  echo "$FILE already exists."
fi
