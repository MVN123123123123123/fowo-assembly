#!/bin/bash

# Update Debug Script
# This script updates the fowo binary and all scripts from the latest source.
# It clones the repo and builds from source so you get the latest changes
# immediately, without waiting for a release.

set -e

REPO_URL="https://github.com/MVN123123123123123/fowo-assembly.git"
WORK_DIR="/tmp/fowo_update_src"

echo "================================================="
echo "  Fowo Live CD Updater"
echo "================================================="
echo ""

# Determine the target script directory
if [ -f /usr/local/bin/install-os.sh ]; then
    SCRIPT_DIR="/usr/local/bin"
elif [ -f "$(dirname "$(realpath "$0")")/install-os.sh" ]; then
    SCRIPT_DIR="$(dirname "$(realpath "$0")")"
else
    SCRIPT_DIR="/usr/local/bin"
fi

echo "[1/4] Cloning latest source..."
rm -rf "$WORK_DIR"
if git clone --depth 1 "$REPO_URL" "$WORK_DIR"; then
    echo "  Source cloned successfully."
else
    echo "  Clone failed. Trying release download fallback..."
    echo "  Downloading pre-built fowo binary..."
    curl -L -o /usr/local/bin/fowo "$REPO_URL/releases/download/latest/fowo" || true
    chmod +x /usr/local/bin/fowo 2>/dev/null || true
    echo "  Downloading install-os.sh..."
    curl -L -o "$SCRIPT_DIR/install-os.sh" "https://raw.githubusercontent.com/MVN123123123123123/fowo-assembly/main/scripts/install-os.sh" || true
    chmod +x "$SCRIPT_DIR/install-os.sh" 2>/dev/null || true
    echo "Update complete (fallback mode)."
    exit 0
fi

echo "[2/4] Building fowo from source..."
if command -v nasm >/dev/null 2>&1 && command -v gcc >/dev/null 2>&1; then
    if make -C "$WORK_DIR" all; then
        echo "  Build successful."
        cp "$WORK_DIR/build/fowo" /usr/local/bin/fowo
        chmod +x /usr/local/bin/fowo
    else
        echo "  Build failed. Trying release download fallback..."
        curl -L -o /usr/local/bin/fowo "https://github.com/MVN123123123123123/fowo-assembly/releases/download/latest/fowo" || true
        chmod +x /usr/local/bin/fowo 2>/dev/null || true
    fi
else
    echo "  nasm/gcc not found. Downloading pre-built binary..."
    curl -L -o /usr/local/bin/fowo "https://github.com/MVN123123123123123/fowo-assembly/releases/download/latest/fowo" || true
    chmod +x /usr/local/bin/fowo 2>/dev/null || true
fi

echo "[3/4] Updating scripts..."
for script in install-os.sh update-debug.sh; do
    if [ -f "$WORK_DIR/scripts/$script" ]; then
        cp "$WORK_DIR/scripts/$script" "$SCRIPT_DIR/$script"
        chmod +x "$SCRIPT_DIR/$script"
        echo "  Updated $script"
        # Also update copy in /root if it exists
        [ -f "/root/$script" ] && cp "$WORK_DIR/scripts/$script" "/root/$script" && chmod +x "/root/$script"
    fi
done
echo "[4/4]Downloading haruka_installer from latest release..."
curl -L -o "$SCRIPT_DIR/haruka_installer" "https://github.com/MVN123123123123123/funny-random-fork/releases/download/latest/haruka_installer" || {
    echo "Warning: Failed to download haruka_installer. It might not be built or published yet."
}
chmod 755 "$SCRIPT_DIR/haruka_installer" 2>/dev/null || true
ln -sf haruka_installer "$SCRIPT_DIR/install-os"
# Clean up
rm -rf "$WORK_DIR"

echo ""
echo "================================================="
echo "  Update complete!"
echo "  fowo: /usr/local/bin/fowo"
echo "  install-os: $SCRIPT_DIR/install-os.sh"
echo "================================================="
echo ""
