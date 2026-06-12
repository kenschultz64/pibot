#!/usr/bin/env bash
set -euo pipefail

# Workspace is the folder where you launch this script from.
export PI_WORKSPACE="${PI_WORKSPACE:-$PWD}"

# Bridge app is the folder where this script lives.
BRIDGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BRIDGE_DIR"

if [[ ! -f .bridge-key ]]; then
  echo "ERROR: .bridge-key not found in $BRIDGE_DIR"
  exit 1
fi

export PI_BRIDGE_API_KEY="${PI_BRIDGE_API_KEY:-$(cat .bridge-key)}"
export HOST="${HOST:-0.0.0.0}"
export PORT="${PORT:-11435}"
export PI_TOOLS="${PI_TOOLS:-read,bash,edit,write,grep,find,ls}"

if [[ -z "${PI_PUBLIC_BASE_URL:-}" ]]; then
  if command -v tailscale >/dev/null 2>&1; then
    TS_IP="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"
  else
    TS_IP=""
  fi
  if [[ -n "$TS_IP" ]]; then
    export PI_PUBLIC_BASE_URL="http://$TS_IP:$PORT"
  else
    export PI_PUBLIC_BASE_URL="http://127.0.0.1:$PORT"
  fi
fi

echo "Starting Pi OpenWebUI Bridge..."
echo "Base URL: ${PI_PUBLIC_BASE_URL}/v1"
echo "Bridge app: $BRIDGE_DIR"
echo "Workspace: $PI_WORKSPACE"
echo "Tools: $PI_TOOLS"
echo

node src/server.js
