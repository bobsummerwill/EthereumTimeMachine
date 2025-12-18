# Chain of Geths

## Goal

The goal of the EthereumTimeMachine project is to sync a Geth 1.0 node by chaining together successively older Geth versions that share overlapping ETH protocols. This allows bridging from the latest PoW-capable Geth (v1.10.23) down to Frontier-era Geth (v1.0.x), enabling historical blockchain data access without requiring every intermediate version.

## Minimal Version Chain

To sync a Geth 1.0 node from the current Ethereum mainnet, we need to bridge from the latest ETH protocol (68) down to ETH 60. The minimal set of versions needed for complete protocol compatibility is:

- **Geth v1.16.7** (ETH 63-68) - Latest version, can peer with current mainnet
- **Geth v1.10.23** (ETH 63) - Latest PoW version, bridges to v1.16 via eth/63
- **Geth v1.8.27** (ETH 62, 63) - Bridges to v1.10 via eth/63, to v1.6 via eth/62
- **Geth v1.6.7** (ETH 61, 62, 63) - Overlaps with v1.8 (eth/62/63) and early versions (eth/61)
- **Geth v1.3.6** (ETH 60, 61, 62) - Bridges to v1.6 (eth/61) and Frontier (eth/60/61)
- **Geth v1.0.x** (ETH 60, 61) - Original Frontier client

This chain ensures every adjacent pair shares at least one protocol version, allowing the top node to sync from mainnet and propagate data down to Geth 1.0.

## Detailed Implementation Plan

### 1. Binary Acquisition

Download the pre-built binaries for each required Geth version from the official Ethereum Go repository releases or gethstore. Run Linux binaries on Ubuntu VMs and Windows binaries on Windows VMs.

- [Geth v1.16.7](https://hub.docker.com/layers/ethereum/client-go/v1.16.7/images/sha256-9dc2db05933ea9b359b4c07960931ef75f42f8f411018c825eb95d882e82fdc1) - Official Docker image ethereum/client-go:v1.16.7 (released 2025-11-04)
- [Geth v1.10.23](https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-1.10.23-d901d853.tar.gz) - geth-linux-amd64-1.10.23-d901d853.tar.gz (released 2022-08-24)
- [Geth v1.8.27](https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-1.8.27-4bcc0a37.tar.gz) - geth-linux-amd64-1.8.27-4bcc0a37.tar.gz (released 2019-04-17)
- [Geth v1.6.7](https://gethstore.blob.core.windows.net/builds/geth-linux-amd64-1.6.7-ab5646c5.tar.gz) - geth-linux-amd64-1.6.7-ab5646c5.tar.gz (released 2017-07-12)
- [Geth v1.3.6](https://github.com/ethereum/go-ethereum/releases/download/v1.3.6/geth-Linux64-20160402135800-1.3.6-9e323d6.tar.bz2) - geth-Linux64-20160402135800-1.3.6-9e323d6.tar.bz2 (released 2016-04-02)
- [Geth v1.0.0](https://github.com/ethereum/go-ethereum/releases/download/v1.0.0/Geth-Win64-20150729141955-1.0.0-0cdc764.zip) - Geth-Win64-20150729141955-1.0.0-0cdc764.zip (released 2015-07-29, run on Windows VM in AWS)

### 2. Docker Compose Setup

Use the `docker-compose.yml` in the `/chain-of-geths/` directory to run the chain. Each service uses an appropriate Ubuntu base image for compatibility.

### 3. AWS Deployment

Deploy on the AWS EC2 instance (m6a.xlarge, Ubuntu 24.04 LTS at 13.220.218.223) for the Linux-based Geth nodes. Create a separate Windows VM in AWS for Geth v1.0.0 using Windows Server 2016 Base Datacenter edition (AMI: ami-0c6fdd9faf0d80ecb) on t2.large instance (2 vCPUs, 8 GiB RAM, suitable for Geth v1.0.0) at 18.232.131.32.

1. Run the `generate-keys.sh` script on a machine with Geth installed to pregenerate node keys and static nodes for consistent enode IDs and automatic peering. This creates the `data/` directory with `nodekey` and `static-nodes.json` files for each version.
2. Install Docker and Docker Compose on the Ubuntu instance.
3. Clone the repository.
4. Navigate to `/chain-of-geths/` and run `docker-compose up -d` (this starts v1.16.7 through v1.3.6).
5. On the Windows VM, install and run Geth v1.0.0 with the pregenerated key, --nodiscover, and --bootnodes with the enode of v1.3.6. Access the Windows VM via RDP: Get the administrator password from the AWS EC2 console, then connect using an RDP client like Remmina (install with `sudo apt install remmina`) on Ubuntu, or Microsoft Remote Desktop on other systems, to the public IP 18.232.131.32.
6. The Docker containers will automatically connect via static nodes.

#### Node Connection Setup

After starting the containers, manually connect them using `admin.addPeer()` via the HTTP RPC interface. Each node needs to peer with the next newer version in the chain to receive blocks.

1. Get the enode URLs from each running node using `admin.nodeInfo.enode`
2. Add peers in reverse chronological order (newer to older)

Example script to wire all containers:
```bash
#!/bin/bash

# v1.10.23 -> v1.16.7
ENODE_1167=$(curl -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' http://localhost:8545 | jq -r '.result.enode')
curl -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addPeer\",\"params\":[\"$ENODE_1167\"],\"id\":1}" http://localhost:8546

# v1.8.27 -> v1.10.23
ENODE_11023=$(curl -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' http://localhost:8546 | jq -r '.result.enode')
curl -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addPeer\",\"params\":[\"$ENODE_11023\"],\"id\":1}" http://localhost:8547

# v1.6.7 -> v1.8.27
ENODE_1827=$(curl -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' http://localhost:8547 | jq -r '.result.enode')
curl -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addPeer\",\"params\":[\"$ENODE_1827\"],\"id\":1}" http://localhost:8548

# v1.3.6 -> v1.6.7
ENODE_167=$(curl -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' http://localhost:8548 | jq -r '.result.enode')
curl -X POST -H "Content-Type: application/json" --data "{\"jsonrpc\":\"2.0\",\"method\":\"admin_addPeer\",\"params\":[\"$ENODE_167\"],\"id\":1}" http://localhost:8549

# v1.0.0 -> v1.3.6 (on Windows VM, adjust URLs accordingly)
ENODE_136=$(curl -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}' http://localhost:8549 | jq -r '.result.enode')
# Run on Windows VM: geth --admin.addPeer $ENODE_136
```

### 5. Validation and Monitoring

- **Handshake Verification**: Check logs for successful peer connections
- **Block Height Monitoring**: Query `eth_blockNumber` on each node to ensure progressive sync
- **Peer Count**: Use `net_peerCount` to verify connections
- **Chain Continuity**: Ensure block hashes match between adjacent nodes

### 6. Potential Challenges and Solutions

- **Build Issues**: Older Go versions may require specific compiler flags or dependency adjustments
- **Protocol Compatibility**: Ensure no breaking changes in devp2p between versions
- **Resource Requirements**: Monitor CPU/memory usage on m6a.large instance
- **Sync Time**: PoW chain sync may take significant time; consider fast sync modes where possible

### 7. Next Steps

- Implement automated peer discovery and connection
- Add health checks and restart policies
- Create monitoring dashboards
- Develop validation scripts for chain integrity
- Document troubleshooting procedures

This plan provides a complete roadmap for achieving the goal of syncing a Geth 1.0 node through a minimal chain of historical versions.