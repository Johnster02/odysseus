#!/bin/bash
# Install Odysseus as a macOS launchd LaunchAgent (the systemd equivalent for
# Apple Silicon / macOS). Runs at login, restarts on crash, no sudo required.
#
#   ./install-service-macos.sh
#
# Override the bind address / port via env vars:
#   ODYSSEUS_HOST=0.0.0.0 ODYSSEUS_PORT=7000 ./install-service-macos.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/com.odysseus.ui.plist"
LABEL="com.odysseus.ui"
DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGDIR="$SCRIPT_DIR/logs"

# Bind to loopback by default (matches the README security guidance). Set
# ODYSSEUS_HOST=0.0.0.0 only if you intentionally want LAN/reverse-proxy access.
HOST="${ODYSSEUS_HOST:-127.0.0.1}"
PORT="${ODYSSEUS_PORT:-7000}"

if [ ! -f "$TEMPLATE" ]; then
  echo "Error: $TEMPLATE not found"
  exit 1
fi

# Prefer the venv uvicorn; fall back to whatever is on PATH.
UVICORN="$SCRIPT_DIR/venv/bin/uvicorn"
if [ ! -x "$UVICORN" ]; then
  UVICORN="$(command -v uvicorn || true)"
fi
if [ -z "$UVICORN" ] || [ ! -x "$UVICORN" ]; then
  echo "Error: uvicorn not found. Create the venv and install requirements first:"
  echo "  python3.11 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents" "$LOGDIR"

echo "Installing Odysseus LaunchAgent..."
echo "  uvicorn:  $UVICORN"
echo "  workdir:  $SCRIPT_DIR"
echo "  bind:     http://$HOST:$PORT"
echo ""

# Fill the template placeholders. Use a non-/ sed delimiter since paths contain /.
sed -e "s|__UVICORN__|$UVICORN|g" \
    -e "s|__WORKDIR__|$SCRIPT_DIR|g" \
    -e "s|__LOGDIR__|$LOGDIR|g" \
    -e "s|__HOST__|$HOST|g" \
    -e "s|__PORT__|$PORT|g" \
    "$TEMPLATE" > "$DEST"

# Reload if already installed.
launchctl unload "$DEST" 2>/dev/null || true
launchctl load "$DEST"

echo "Loaded $LABEL -> http://$HOST:$PORT"
echo ""
echo "Logs:    tail -f $LOGDIR/odysseus.out.log"
echo "Status:  launchctl list | grep odysseus"
echo "Stop:    launchctl unload $DEST"
echo "Restart: launchctl unload $DEST && launchctl load $DEST"
