#!/usr/bin/env bash
set -euo pipefail

NAME="${NAME:-pibot}"
HOST_PORT="${HOST_PORT:-11436}"
PUBLIC_BASE_URL="${PI_PUBLIC_BASE_URL:-http://127.0.0.1:${HOST_PORT}}"
IMAGE="${IMAGE:-pibot:latest}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [[ ! -f .bridge-key ]]; then
  printf 'pi-%s\n' "$(openssl rand -hex 16)" > .bridge-key
  chmod 600 .bridge-key || true
  echo "Created .bridge-key"
fi

if [[ ! -f .file-key ]]; then
  printf 'file-%s\n' "$(openssl rand -hex 16)" > .file-key
  chmod 600 .file-key || true
  echo "Created .file-key"
fi

BRIDGE_KEY="$(tr -d '\r\n' < .bridge-key)"
FILE_KEY="$(tr -d '\r\n' < .file-key)"

echo "Building $IMAGE..."
docker build -f Dockerfile.pi-bridge -t "$IMAGE" .

echo "Removing old $NAME container if present..."
docker rm -f "$NAME" >/dev/null 2>&1 || true

echo "Starting $NAME on port $HOST_PORT..."
docker run -d \
  --name "$NAME" \
  --restart unless-stopped \
  -p "${HOST_PORT}:11435" \
  -e PI_BRIDGE_API_KEY="$BRIDGE_KEY" \
  -e PI_FILE_DOWNLOAD_KEY="$FILE_KEY" \
  -e PI_PUBLIC_BASE_URL="$PUBLIC_BASE_URL" \
  -e PI_WORKSPACE="/workspace" \
  -e PI_TOOLS="read,bash,edit,write,grep,find,ls" \
  -v "${NAME}-workspace:/workspace" \
  -v "$HOME/.pi/agent:/root/.pi/agent" \
  "$IMAGE"

echo
echo "Open WebUI Base URL: ${PUBLIC_BASE_URL}/v1"
echo "Open WebUI API Key: contents of .bridge-key"
echo "Container workspace: /workspace"
