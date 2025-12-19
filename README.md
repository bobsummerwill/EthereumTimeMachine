# EthereumTimeMachine
Tools to revive Ethereum Frontier and Homestead chains

## Chain of Geths

This repository currently focuses on the **"Chain of Geths"** approach: run multiple historical Geth versions that share overlapping `eth/*` protocol versions, allowing a modern node to sync from mainnet and propagate chain data down to progressively older clients.

Start here:
- Design/plan: `chain-of-geths/chain-of-geths.md`
- Docker Compose stack (v1.16.7 → v1.3.6): `chain-of-geths/docker-compose.yml`
- Automation scripts: `chain-of-geths/generate-keys.sh`, `chain-of-geths/build-images.sh`, `chain-of-geths/deploy.sh`

Note: **Geth v1.0.x is run on Windows** (no maintained pre-built Linux binaries). The Windows node is bootstrapped to the chain by connecting to the Ubuntu host's Geth v1.3.6 via `--bootnodes`.
