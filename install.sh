#!/usr/bin/env bash
set -euo pipefail

echo "============================================"
echo "  Binance Futures Trading System Installer"
echo "  macOS Apple Silicon"
echo "============================================"
echo ""

# Check for Homebrew
if ! command -v brew &>/dev/null; then
    echo "[INFO] Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add brew to PATH for Apple Silicon
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    echo "[OK] Homebrew found: $(brew --version | head -1)"
fi

# Install or update Python 3.11
if brew list python@3.11 &>/dev/null; then
    echo "[OK] Python 3.11 already installed, updating..."
    brew upgrade python@3.11 || true
else
    echo "[INFO] Installing Python 3.11..."
    brew install python@3.11
fi

PYTHON=$(brew --prefix python@3.11)/bin/python3.11
echo "[OK] Using Python: $PYTHON ($($PYTHON --version))"

# Create virtual environment
VENV_DIR="$(dirname "$0")/venv"
if [ -d "$VENV_DIR" ]; then
    echo "[INFO] Virtual environment already exists at $VENV_DIR"
else
    echo "[INFO] Creating virtual environment at $VENV_DIR..."
    $PYTHON -m venv "$VENV_DIR"
fi

# Activate venv
source "$VENV_DIR/bin/activate"
echo "[OK] Virtual environment activated"

# Upgrade pip
pip install --upgrade pip --quiet

# Install requirements
echo "[INFO] Installing Python dependencies..."
pip install -r "$(dirname "$0")/requirements.txt"
echo "[OK] Dependencies installed"

# Copy .env.example to .env if not present
ENV_FILE="$(dirname "$0")/.env"
ENV_EXAMPLE="$(dirname "$0")/.env.example"
if [ ! -f "$ENV_FILE" ]; then
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    echo "[OK] Created .env from .env.example — please edit it with your API keys"
else
    echo "[OK] .env already exists, skipping copy"
fi

# Create database directory if needed
mkdir -p "$(dirname "$0")/database"

echo ""
echo "============================================"
echo "  Installation Complete!"
echo "============================================"
echo ""
echo "Usage:"
echo "  1. Activate venv:       source venv/bin/activate"
echo "  2. Edit config:         nano .env"
echo "  3. Run paper trading:   python main.py"
echo "  4. Run with dashboard:  python main.py  (opens browser automatically)"
echo "  5. Run live trading:    python main.py --live  (requires API keys in .env)"
echo "  6. Single symbol:       python main.py --symbol BTCUSDT"
echo "  7. No dashboard:        python main.py --no-dashboard"
echo ""
echo "Dashboard URL: http://localhost:8501"
echo ""
