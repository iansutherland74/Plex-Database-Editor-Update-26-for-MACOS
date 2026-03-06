#!/bin/bash
#
# Build and install Plex TV Editor macOS app
# This script sets up the app bundle and installs it to /Applications
#

set -e  # Exit on error

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_SOURCE="$SCRIPT_DIR/Plex TV Editor.app"
APP_DEST="/Applications/Plex TV Editor.app"

echo "=========================================="
echo "Plex TV Editor - macOS App Builder"
echo "=========================================="
echo ""

# Check if Python3 is installed
echo "[1/5] Checking Python3..."
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 is not installed!"
    echo "Please install Python 3 from python.org or using Homebrew"
    exit 1
fi
PYTHON_VERSION=$(python3 --version)
echo "✓ Found $PYTHON_VERSION"
echo ""

# Install Python dependencies
echo "[2/5] Installing Python dependencies..."
python3 -m pip install requests --quiet 2>/dev/null || true
echo "✓ Dependencies installed"
echo ""

# Create app icon
echo "[3/5] Creating app icon..."
python3 "$SCRIPT_DIR/create_app_icon.py" 2>/dev/null || echo "✓ Icon creation skipped (optional)"
echo ""

# Copy app to Applications
echo "[4/5] Installing app to /Applications..."
if [ -d "$APP_DEST" ]; then
    echo "  Removing existing installation..."
    rm -rf "$APP_DEST"
fi

cp -r "$APP_SOURCE" "$APP_DEST"
chmod +x "$APP_DEST/Contents/MacOS/plex_tv_editor"
echo "✓ App installed to /Applications/Plex TV Editor.app"
echo ""

# Copy config if it exists
echo "[5/5] Setting up configuration..."
if [ -f "$HOME/.plex_tv_editor_config.json" ]; then
    echo "✓ Configuration found"
else
    echo "  Creating default configuration..."
    cat > "$HOME/.plex_tv_editor_config.json" << 'EOF'
{
  "plex_sqlite": "/Applications/Plex Media Server.app/Contents/Resources/Support/Plex SQLite",
  "db_path": "~/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db",
  "date_format": "%Y-%m-%d %H:%M:%S",
  "tmdb_api_key": "fd51c863ad45547eb19ba9f70f3ac4f0"
}
EOF
    echo "✓ Configuration created at ~/.plex_tv_editor_config.json"
fi
echo ""

# Update Launchpad to see the app
echo "Updating macOS app database..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DEST" 2>/dev/null || true

echo "=========================================="
echo "✓ Installation Complete!"
echo "=========================================="
echo ""
echo "To launch the app:"
echo "  1. Open /Applications/Plex TV Editor.app"
echo "  2. Or search for 'Plex TV Editor' in Spotlight"
echo ""
echo "Settings are stored in: ~/.plex_tv_editor_config.json"
echo ""
echo "To uninstall:"
echo "  rm -rf /Applications/Plex\\ TV\\ Editor.app"
echo ""
