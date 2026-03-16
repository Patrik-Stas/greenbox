#!/usr/bin/env bash
set -euo pipefail

# Read config
GREENBOX_CONFIG="$(dirname "$0")/.greenbox"
if [ ! -f "$GREENBOX_CONFIG" ]; then
  echo "Error: .greenbox config not found"
  exit 1
fi
NAME=$(grep '^name=' "$GREENBOX_CONFIG" | cut -d= -f2)
CONFIGURED_PORT=$(grep '^port=' "$GREENBOX_CONFIG" | cut -d= -f2)
CONFIGURED_PORT="${CONFIGURED_PORT:-3100}"

CONTAINER_NAME="greenbox-${NAME}"
DEV=false
NO_CACHE=false

for arg in "$@"; do
  case "$arg" in
    --dev)   DEV=true ;;
    --no-cache) NO_CACHE=true ;;
  esac
done

# Verify Claude credentials
CLAUDE_CREDS="$HOME/.claude_mine/.credentials.json"
if [ ! -f "$CLAUDE_CREDS" ]; then
  echo "Error: $CLAUDE_CREDS not found."
  echo "Run: greenbox setup-creds"
  exit 1
fi

# Create data dir
mkdir -p data

# Find first free host port
PORT="$CONFIGURED_PORT"
MAX_PORT=$((CONFIGURED_PORT + 20))
while lsof -iTCP:"$PORT" -sTCP:LISTEN -t >/dev/null 2>&1; do
  ((PORT++))
  if [ "$PORT" -gt "$MAX_PORT" ]; then
    echo "Error: no free port found in range ${CONFIGURED_PORT}-${MAX_PORT}"
    exit 1
  fi
done

# Build
CACHE_FLAG=""
if [ "$NO_CACHE" = true ]; then
  CACHE_FLAG="--no-cache"
fi

if [ "$DEV" = true ]; then
  docker build $CACHE_FLAG --target dev -t "greenbox-${NAME}:dev" .
else
  docker build $CACHE_FLAG --target prod -t "greenbox-${NAME}:latest" .
fi

# Stop existing container if running
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

# Remove stale node_modules volume on rebuild
if [ "$NO_CACHE" = true ]; then
  docker volume rm "greenbox-${NAME}-node_modules" 2>/dev/null || true
fi

# Env file
ENV_ARGS=()
if [ -f .env ]; then
  ENV_ARGS=(--env-file .env)
fi

# Run
if [ "$DEV" = true ]; then
  docker run -d \
    --name "$CONTAINER_NAME" \
    -p "$PORT:$CONFIGURED_PORT" \
    "${ENV_ARGS[@]+"${ENV_ARGS[@]}"}" \
    -v "$CLAUDE_CREDS:/home/node/.claude/.credentials.json:ro" \
    -v "$(pwd):/app" \
    -v "greenbox-${NAME}-node_modules:/app/node_modules" \
    -v "$(pwd)/data:/app/data" \
    "greenbox-${NAME}:dev"
else
  docker run -d \
    --name "$CONTAINER_NAME" \
    -p "$PORT:$CONFIGURED_PORT" \
    "${ENV_ARGS[@]+"${ENV_ARGS[@]}"}" \
    -v "$CLAUDE_CREDS:/home/node/.claude/.credentials.json:ro" \
    -v "$(pwd)/data:/app/data" \
    "greenbox-${NAME}:latest"
fi

echo ""
echo "Running at http://localhost:$PORT"
if [ "$DEV" = true ]; then
  echo "Mode: dev (live reload)"
fi
echo ""

docker logs -f "$CONTAINER_NAME"
