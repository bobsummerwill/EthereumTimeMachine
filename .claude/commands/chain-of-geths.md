# Chain of Geths

Build and deploy historical geth Docker images for the Ethereum Time Machine.

## Directory

`chain-of-geths/`

## Key Scripts

- `build-images.sh` - Build Docker images for specific geth versions
- `deploy.sh` - Deploy the geth network
- `docker-compose.yml` - Multi-node geth network configuration
- `generate-keys.sh` - Generate node keys and accounts
- `start-legacy-staged.sh` - Staged startup for legacy nodes

## Instructions

1. Read `chain-of-geths/README.md` for full documentation
2. To build a specific geth version:
   ```bash
   cd chain-of-geths && ONLY_VERSION=v1.0.2 ./build-images.sh
   ```
3. To deploy the network:
   ```bash
   cd chain-of-geths && ./deploy.sh
   ```
4. Check `.env.example` for required environment variables

## Supported Geth Versions

The project supports multiple historical geth versions to sync with different Ethereum eras:
- v1.0.2 - Frontier
- v1.3.6 - Homestead
- v1.4.x - Later versions
