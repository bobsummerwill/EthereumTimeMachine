#!/bin/bash

# Script to generate node keys and static nodes for Geth chain
# Run this on a machine with geth installed

set -e

# Versions and their IPs
declare -A versions=(
    ["v1.16.7"]="172.20.0.10:30303"
    ["v1.10.23"]="172.20.0.11:30304"
    ["v1.8.27"]="172.20.0.12:30305"
    ["v1.6.7"]="172.20.0.13:30306"
    ["v1.3.6"]="172.20.0.14:30307"
)

# Ubuntu external IP for connecting to v1.3.6 from Windows
EXTERNAL_IP="13.220.218.223"
WINDOWS_PORT="30308"

# Function to generate nodekey and get enode
generate_enode() {
    local version=$1
    local datadir="data/$version"
    mkdir -p "$datadir"

    # Start geth briefly to generate nodekey
    timeout 10s geth --datadir "$datadir" --http --http.api admin 2>/dev/null || true

    # Get enode
    enode=$(geth --nodekey "$datadir/nodekey" dump-enode 2>/dev/null)
    echo "$enode"
}

# Generate for each version
declare -A enodes
for version in "${!versions[@]}"; do
    echo "Generating key for $version..."
    enode=$(generate_enode "$version")
    enodes[$version]="$enode"
    echo "Enode for $version: $enode"
done

# Create static-nodes.json for each older version
for version in v1.10.23 v1.8.27 v1.6.7 v1.3.6; do
    case $version in
        v1.10.23) next="v1.16.7" ;;
        v1.8.27) next="v1.10.23" ;;
        v1.6.7) next="v1.8.27" ;;
        v1.3.6) next="v1.6.7" ;;
    esac

    datadir="data/$version"
    echo "[\"${enodes[$next]}\"]" > "$datadir/static-nodes.json"
    echo "Created static-nodes.json for $version pointing to $next"
done

# For v1.0.0 (Windows), output the enode of v1.3.6 for connection
v1_3_6_enode="${enodes[v1.3.6]}"
# Replace the IP with external IP
windows_enode=$(echo "$v1_3_6_enode" | sed "s/@[^:]*:/@$EXTERNAL_IP:/")
echo "$windows_enode" > windows_enode.txt
echo ""
echo "For Windows Geth v1.0.0, use this enode to connect to v1.3.6:"
echo "$windows_enode"
echo ""
echo "PowerShell command for Windows VM:"
echo "\$enode = '$windows_enode'"
echo "geth --datadir C:\\geth-data --nodiscover --bootnodes \$enode --http --http.api eth,net,web3 --syncmode full --networkid 1"
echo ""
echo "Download Geth v1.0.0 to C:\\geth\\ and run the above command."

echo "Key generation complete. Copy the data/ directory to the deployment location."