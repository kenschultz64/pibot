#!/usr/bin/env bash
set -euo pipefail

NAME="${NAME:-pibot}"
HOST_PORT="${HOST_PORT:-11436}"
BIND_HOST="${BIND_HOST:-127.0.0.1}"
PUBLIC_BASE_URL="${PI_PUBLIC_BASE_URL:-http://127.0.0.1:${HOST_PORT}}"
IMAGE="${IMAGE:-pibot:latest}"
PI_AGENT_DIR="${PI_AGENT_DIR:-$HOME/.pi/agent}"
PI_TOOLS="${PI_TOOLS:-read,bash,edit,write,grep,find,ls}"
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

echo "Starting $NAME on ${BIND_HOST}:${HOST_PORT}..."
docker run -d \
  --name "$NAME" \
  --restart unless-stopped \
  --user node \
  --cap-drop=ALL \
  --security-opt no-new-privileges:true \
  -p "${BIND_HOST}:${HOST_PORT}:11435" \
  -e PI_BRIDGE_API_KEY="$BRIDGE_KEY" \
  -e PI_FILE_DOWNLOAD_KEY="$FILE_KEY" \
  -e PI_PUBLIC_BASE_URL="$PUBLIC_BASE_URL" \
  -e PI_WORKSPACE="/workspace" \
  -e PI_TOOLS="$PI_TOOLS" \
  -e HOME="/home/node" \
  -v "${NAME}-workspace:/workspace" \
  -v "$PI_AGENT_DIR:/home/node/.pi/agent:ro" \
  "$IMAGE"

echo
echo "Open WebUI Base URL: ${PUBLIC_BASE_URL}/v1"
echo "Open WebUI API Key: contents of .bridge-key"
echo "Container workspace: /workspace"
echo "Bound host interface: ${BIND_HOST}"
echo "Pi auth/config mount: ${PI_AGENT_DIR} -> /home/node/.pi/agent:ro"
