#!/usr/bin/env bash
set -euo pipefail

# ToolHarness Launcher
# Starts the ToolHarness container for local use.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV_FILE=".env"
PORT="${TOOLHARNESS_PORT:-3000}"

# Detect container runtime
if command -v docker &>/dev/null; then
  RUNTIME="docker"
  COMPOSE="docker compose"
elif command -v podman &>/dev/null; then
  RUNTIME="podman"
  if command -v podman-compose &>/dev/null; then
    COMPOSE="podman-compose"
  else
    echo "Error: podman-compose is required when using Podman."
    echo "Install it with: pip install podman-compose"
    exit 1
  fi
else
  echo "Error: Neither Docker nor Podman found."
  echo "Install Docker: https://docs.docker.com/engine/install/"
  exit 1
fi

echo "=== ToolHarness ==="
echo "Using: $RUNTIME"

# Generate .env file if it doesn't exist
if [ ! -f "$ENV_FILE" ]; then
  echo "Generating $ENV_FILE..."
  SECRET_KEY_BASE=$(openssl rand -hex 64)
  cat > "$ENV_FILE" <<EOF
SECRET_KEY_BASE=$SECRET_KEY_BASE
TOOLHARNESS_DEFAULT_USER_EMAIL=admin@localhost
TOOLHARNESS_DEFAULT_USER_PASSWORD=changeme123
TOOLHARNESS_PORT=$PORT
EOF
  echo "Created $ENV_FILE with default settings."
  echo "  Email:    admin@localhost"
  echo "  Password: changeme123"
  echo ""
fi

# Source .env for PORT variable
set -a
source "$ENV_FILE"
set +a

PORT="${TOOLHARNESS_PORT:-3000}"

# Build and start
echo "Building and starting ToolHarness..."
$COMPOSE up -d --build

# Wait for health
echo "Waiting for ToolHarness to be ready..."
MAX_WAIT=60
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
  if curl -sf "http://localhost:$PORT/up" &>/dev/null; then
    break
  fi
  sleep 2
  WAITED=$((WAITED + 2))
  printf "."
done
echo ""

if [ $WAITED -ge $MAX_WAIT ]; then
  echo "Warning: ToolHarness may not be fully ready yet."
  echo "Check logs with: $COMPOSE logs"
else
  echo "ToolHarness is running!"
fi

echo ""
echo "  URL: http://localhost:$PORT"
echo "  Stop: $COMPOSE down"
echo ""

# Open browser
if command -v xdg-open &>/dev/null; then
  xdg-open "http://localhost:$PORT" 2>/dev/null &
elif command -v open &>/dev/null; then
  open "http://localhost:$PORT" 2>/dev/null &
fi
