#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-11435}"
BRIDGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$BRIDGE_DIR/bridge.pid"

echo "Stopping Pi OpenWebUI Bridge on port $PORT..."

if [[ -f "$PID_FILE" ]]; then
  PID="$(cat "$PID_FILE")"
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    echo "Stopping PID $PID from bridge.pid"
    kill "$PID" 2>/dev/null || true
    sleep 1
    if kill -0 "$PID" 2>/dev/null; then
      echo "Force stopping PID $PID"
      kill -9 "$PID" 2>/dev/null || true
    fi
  fi
  rm -f "$PID_FILE"
fi

if command -v lsof >/dev/null 2>&1; then
  PIDS="$(lsof -ti tcp:"$PORT" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$PIDS" ]]; then
    echo "$PIDS" | while read -r PID; do
      [[ -z "$PID" ]] && continue
      echo "Stopping listener PID $PID"
      kill "$PID" 2>/dev/null || true
    done
  fi
elif command -v fuser >/dev/null 2>&1; then
  fuser -k "${PORT}/tcp" 2>/dev/null || true
else
  echo "Note: install lsof or psmisc/fuser for port-based stopping."
fi

echo "Done."
