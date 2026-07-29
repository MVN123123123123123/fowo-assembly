#!/bin/bash

# Update Debug Script
# This script downloads the latest fowo binary and install-os.sh script
# from the main repository, so you can test changes on the Live CD without rebuilding the ISO.

echo "Downloading latest fowo binary from GitHub releases..."
curl -L -o /usr/local/bin/fowo https://github.com/MVN123123123123123/fowo-assembly/releases/download/latest/fowo
chmod +x /usr/local/bin/fowo

echo "Downloading latest install-os.sh from GitHub main branch..."
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
curl -L -o "$SCRIPT_DIR/install-os.sh" https://raw.githubusercontent.com/MVN123123123123123/fowo-assembly/main/scripts/install-os.sh
chmod +x "$SCRIPT_DIR/install-os.sh"

echo "Update complete!"
echo "fowo version: $(/usr/local/bin/fowo version 2>/dev/null || echo 'Unknown')"
echo "You can now run $SCRIPT_DIR/install-os.sh to test the latest changes."
