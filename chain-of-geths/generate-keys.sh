#!/bin/bash

# Script to generate node keys and static nodes for Geth chain
# Run this on a machine with Docker installed (it uses a recent geth container to run dump-enode)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Versions and their (docker-network) IPs/ports. Must match docker-compose.yml.
versions=(v1.16.7 v1.10.23 v1.8.27 v1.6.7 v1.3.6)
declare -A ip_by_version=(
    ["v1.16.7"]="172.20.0.10"
    ["v1.10.23"]="172.20.0.11"
    ["v1.8.27"]="172.20.0.12"
    ["v1.6.7"]="172.20.0.13"
    ["v1.3.6"]="172.20.0.14"
)
declare -A port_by_version=(
    ["v1.16.7"]="30303"
    ["v1.10.23"]="30304"
    ["v1.8.27"]="30305"
    ["v1.6.7"]="30306"
    ["v1.3.6"]="30307"
)

# Ubuntu external IP for connecting to v1.3.6 from Windows
EXTERNAL_IP="13.220.218.223"
WINDOWS_PORT="${port_by_version[v1.3.6]}"

# Function to generate nodekey and get enode using Docker
generate_enode() {
    local version=$1
    local datadir="data/$version"
    local ip="${ip_by_version[$version]}"
    local port="${port_by_version[$version]}"
    mkdir -p "$datadir"

    # Start geth briefly to generate nodekey using Docker
    timeout 10s docker run --rm -v "$(pwd)/$datadir:/data" ethereum/client-go:v1.16.7 --datadir /data --http --http.api admin 2>/dev/null || true

    # Get enode using Docker
    local raw
    raw=$(docker run --rm -v "$(pwd)/$datadir:/data" ethereum/client-go:v1.16.7 --nodekey /data/nodekey --port "$port" dump-enode 2>/dev/null)
    # dump-enode returns something like: enode://<pubkey>@[::]:30303
    # Normalize to a usable address in our docker-compose network.
    local pubkey
    pubkey=$(echo "$raw" | sed -E 's#^enode://([^@]+)@.*#\1#')
    echo "enode://$pubkey@$ip:$port"
}

# Generate for each version
declare -A enodes
for version in "${versions[@]}"; do
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
    printf '["%s"]\n' "${enodes[$next]}" > "$datadir/static-nodes.json"
    echo "Created static-nodes.json for $version pointing to $next"
done

# For v1.0.0 (Windows), output the enode of v1.3.6 for connection
v1_3_6_enode="${enodes[v1.3.6]}"
# Replace the docker-network IP with the VM's public IP so the Windows VM can reach it.
# Port remains the published p2p port for v1.3.6.
windows_enode=$(echo "$v1_3_6_enode" | sed -E "s/@[^:]+:/@$EXTERNAL_IP:/")
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
