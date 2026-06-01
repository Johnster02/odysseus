#!/bin/bash
# Odysseus — one-command quick start for macOS (Apple Silicon).
#
#   ./start-macos.sh
#
# Installs everything Odysseus needs via Homebrew, sets up a local Python
# environment, and launches the app — so a generic Mac user can run it without
# knowing anything about venvs, pip, or uvicorn. Safe to re-run; it skips work
# that's already done.
#
# Why native (not Docker): Cookbook serves models on whatever machine Odysseus
# runs on, and Docker on macOS is a Linux VM with no access to the Metal GPU.
# Running natively lets Cookbook detect and use your Mac's GPU.
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

PORT="${ODYSSEUS_PORT:-7860}"   # 7860, not 7000 — macOS AirPlay Receiver holds 7000.

echo "▶ Odysseus quick start for macOS"

# 1. Homebrew — the macOS package manager. We can't safely auto-install it
#    (it wants its own interactive confirmation), so point the user at it.
if ! command -v brew >/dev/null 2>&1; then
  echo
  echo "Homebrew is required but not installed. Install it (one command), then re-run this script:"
  echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  echo
  echo "More info: https://brew.sh"
  exit 1
fi

# 2. System dependencies:
#    - python@3.11 : the app needs 3.11+ (system Python is older)
#    - tmux        : Cookbook runs model downloads/serves in the background
#    - llama.cpp   : a prebuilt, Metal-enabled llama-server so Cookbook can
#                    serve GGUF models on the GPU with no compile step
echo "▶ Installing dependencies (Homebrew)…"
brew install python@3.11 tmux llama.cpp

PY="$(command -v python3.11 || command -v python3)"

# 3. Python environment + dependencies (kept inside the repo, in .venv).
if [ ! -d .venv ]; then
  echo "▶ Creating Python environment…"
  "$PY" -m venv .venv
fi
echo "▶ Installing Python packages…"
./.venv/bin/python -m pip install --quiet --upgrade pip
./.venv/bin/python -m pip install --quiet -r requirements.txt

# 4. First-run setup: creates data dirs and prints an initial admin password
#    the first time (idempotent — does nothing if already set up).
echo "▶ Preparing Odysseus…"
./.venv/bin/python setup.py

# 5. Launch. Bind to loopback only (safe default); the user opens the URL below.
echo
echo "✓ Odysseus is starting. Open this in your browser:"
echo "    http://127.0.0.1:$PORT"
echo "  (Press Ctrl+C here to stop it.)"
echo
exec ./.venv/bin/python -m uvicorn app:app --host 127.0.0.1 --port "$PORT"
