#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="greenbox"
CONTAINER_PORT=3100
DEV=false

if [ "${1:-}" = "--dev" ]; then
  DEV=true
fi

# Verify Claude credentials
CLAUDE_CREDS="$HOME/.claude_mine/.credentials.json"
if [ ! -f "$CLAUDE_CREDS" ]; then
  echo "Error: $CLAUDE_CREDS not found."
  echo "Run ./setup-creds.sh and paste your credentials into it."
  exit 1
fi

# Find first free host port starting at 3000
PORT=3000
while lsof -iTCP:"$PORT" -sTCP:LISTEN -t >/dev/null 2>&1; do
  ((PORT++))
  if [ "$PORT" -gt 3100 ]; then
    echo "Error: no free port found in range 3000-3100"
    exit 1
  fi
done

# Build
if [ "$DEV" = true ]; then
  ./build.sh dev
else
  ./build.sh
fi

# Stop existing container if running
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

# Run
if [ "$DEV" = true ]; then
  docker run -d \
    --name "$CONTAINER_NAME" \
    -p "$PORT:$CONTAINER_PORT" \
    --env-file .env \
    -v "$CLAUDE_CREDS:/home/node/.claude/.credentials.json:ro" \
    -v "$(pwd)/server.js:/app/server.js:ro" \
    -v "$(pwd)/data:/app/data" \
    greenbox:dev
else
  docker run -d \
    --name "$CONTAINER_NAME" \
    -p "$PORT:$CONTAINER_PORT" \
    --env-file .env \
    -v "$CLAUDE_CREDS:/home/node/.claude/.credentials.json:ro" \
    -v "$(pwd)/data:/app/data" \
    greenbox
fi

echo ""
echo "Server running at http://localhost:$PORT"
if [ "$DEV" = true ]; then
  echo "Mode: dev (live reload — edit files and save)"
fi
echo "Logs: docker logs -f $CONTAINER_NAME"
