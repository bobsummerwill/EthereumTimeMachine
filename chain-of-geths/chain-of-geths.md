# Chain of Geths

## Goal

The goal of the EthereumTimeMachine project is to sync a Geth 1.0 node by chaining together successively older Geth versions that share overlapping ETH protocols. This allows bridging from the latest PoS-capable node down to Frontier-era Geth (v1.0.x), enabling historical blockchain data access without requiring every intermediate version.

## Minimal Version Chain

To sync a Geth 1.0 node from the current Ethereum mainnet, we need to bridge from the latest ETH protocol (68) down to ETH 60. The minimal set of versions needed for complete protocol compatibility is:

- **Geth v1.16.7** (ETH 68, 69) - Latest version, can peer with current mainnet
- **Geth v1.11.6** (ETH 66, 67, 68) - Bridges `v1.16.7` ↔ `v1.10.0`
- **Geth v1.10.0** (ETH 64, 65, 66) - Bridges `v1.11.6` ↔ `v1.9.25`
- **Geth v1.9.25** (ETH 63, 64, 65) - Bridges `v1.10.0` ↔ `v1.3.6`
- **Geth v1.3.6** (ETH 61, 62, 63) - Oldest Linux node in the Compose stack
- **Geth v1.0.x** (ETH 60, 61) - Original Frontier client

This chain ensures every adjacent pair shares at least one protocol version, allowing the top node to sync from mainnet and propagate data down to Geth 1.0.

Notes on protocol compatibility:
- `v1.16.7` supports `eth/68` and `eth/69`, so it cannot peer directly with `v1.10.0` (`eth/64`, `eth/65`, `eth/66`).
- `v1.11.6` is inserted specifically because it supports `eth/66`, `eth/67`, and `eth/68`.
- `v1.10.0` also cannot peer directly with `v1.3.6` (`eth/61`, `eth/62`, `eth/63`), so `v1.9.25` is used to bridge `eth/65 → eth/63`.

## Detailed Implementation Plan

### 1. Automated Setup

The entire setup is automated using the scripts in the `/chain-of-geths/` directory:

- `generate-keys.sh`: Generates node keys and static nodes for automatic peering
- `build-images.sh`: Builds Docker images with downloaded binaries
- `deploy.sh`: Deploys everything to AWS VMs

Notes:
- The Docker Compose stack runs **v1.16.7 → v1.3.6** only. Geth **v1.0.x is run on Windows**, since there are no maintained pre-built Linux binaries.
- The bridge from Windows (v1.0.x) into the chain is done by pointing v1.0.x at the Ubuntu host's **v1.3.6 p2p port** via `--bootnodes`.

### 2. AWS Deployment

Deployment is fully automated using the `deploy.sh` script from your local machine. It handles:

- Pregenerating node keys and static nodes for consistent enode IDs and automatic peering
- Building Docker images locally
- Deploying to the Ubuntu AWS EC2 instance (m6a.2xlarge at 54.81.90.194)
- Starting the Docker Compose chain (v1.16.7 through v1.3.6) with automatic container wiring via static nodes
- Remotely setting up Geth v1.0.0 on the Windows VM (t2.large at 18.232.131.32) via AWS Systems Manager

Run `./chain-of-geths/deploy.sh` after updating `SSH_KEY_PATH` and ensuring AWS CLI is configured.


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
