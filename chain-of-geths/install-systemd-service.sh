#!/bin/bash

# Install the Chain of Geths systemd service for automatic startup on boot
# Run this on the VM after deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing Chain of Geths systemd service..."

# Copy service file
sudo cp "$SCRIPT_DIR/chain-of-geths.service" /etc/systemd/system/

# Ensure startup script is executable
chmod +x "$SCRIPT_DIR/startup.sh"

# Reload systemd and enable the service
sudo systemctl daemon-reload
sudo systemctl enable chain-of-geths.service

echo ""
echo "Service installed and enabled."
echo ""
echo "Commands:"
echo "  sudo systemctl start chain-of-geths   # Start now"
echo "  sudo systemctl status chain-of-geths  # Check status"
echo "  sudo systemctl stop chain-of-geths    # Stop"
echo "  journalctl -u chain-of-geths -f       # View logs"
echo ""
echo "The service will now start automatically on boot."
