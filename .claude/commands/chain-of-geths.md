# Chain of Geths

Build and deploy historical geth Docker images for the Ethereum Time Machine.

## Directory

`chain-of-geths/`

## Key Scripts

- `build-images.sh` - Build Docker images for specific geth versions
- `deploy.sh` - Deploy the geth network to AWS VM
- `docker-compose.yml` - Multi-node geth network configuration
- `generate-keys.sh` - Generate node keys and accounts
- `start-legacy-staged.sh` - Staged startup for legacy nodes
- `generate-geth-1.3.6-windows.sh` - Generate Windows bundle for external sync

## Build and Deploy

```bash
cd chain-of-geths

# Build a specific geth version
ONLY_VERSION=v1.3.6 ./build-images.sh

# Generate node keys (required before deploy)
./generate-keys.sh

# Deploy to AWS VM (requires .env with VM_IP)
./deploy.sh
```

## Generate Windows Bundle

For Windows users to sync with the chain-of-geths network:

```bash
cd chain-of-geths
./generate-geth-1.3.6-windows.sh
```

Output: `generated-files/geth-windows-v1.3.6.zip`

## Configuration

Create `.env` from `.env.example`:
```bash
VM_IP=35.173.251.232
VM_USER=ubuntu
SSH_KEY_PATH=$HOME/Downloads/chain-of-geths-keys.pem
```

## Supported Geth Versions

| Version | Era | Protocol | Notes |
|---------|-----|----------|-------|
| v1.0.2 | Frontier | eth/60 | Genesis-compatible |
| v1.3.6 | Homestead | eth/61-63 | Pre-DAO fork |
| v1.4.x | Homestead+ | eth/61-63 | Post-DAO fork support |
| v1.16.7 | Modern | eth/68 | Current mainnet sync |

## Docker Compose Services

- `geth-v1-16-7` - Modern head-syncing node
- `lighthouse-v8-0-1` - Consensus client for post-Merge
- `geth-v1-3-6` - Homestead-era node (port 30311)
- `geth-v1-0-2` - Frontier-era node (port 30310)
- `grafana` - Monitoring dashboard
- `prometheus` - Metrics collection

## Network Topology

```
Modern mainnet → v1.16.7 → v1.3.6 → v1.0.2
                    ↓
              lighthouse (CL)
```
