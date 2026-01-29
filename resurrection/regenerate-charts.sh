#!/bin/bash
# Regenerate resurrection charts with current data from the sync node.
#
# Usage:
#   cd resurrection
#   ./regenerate-charts.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Activate virtual environment
if [ -d ".venv" ]; then
    source .venv/bin/activate
else
    echo "Error: .venv not found. Run: python3 -m venv .venv && pip install matplotlib"
    exit 1
fi

# Run the Python script
python3 regenerate-charts.py
