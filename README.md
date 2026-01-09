# EthereumTimeMachine
Tools to run historical Ethereum clients and related workflows.

## Overview

The Ethereum Time Machine project enables running authentic historical Ethereum software on contemporary hardware. It consists of two main phases:

1. **Chain of Geths** - Protocol bridge infrastructure to sync historical chaindata
2. **Resurrection** - GPU mining to extend historical chains to CPU-mineable difficulty

## Chain of Geths

A Docker Compose stack of multiple Geth versions (plus Lighthouse) where adjacent nodes share overlapping `eth/*` subprotocols, enabling modern clients to sync historical chaindata to ancient Geth versions.

Documentation: [`chain-of-geths/README.md`](chain-of-geths/README.md)

Entrypoints:
- Compose stack: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml)
- Key/config generation: [`chain-of-geths/generate-keys.sh`](chain-of-geths/generate-keys.sh)
- Image build: [`chain-of-geths/build-images.sh`](chain-of-geths/build-images.sh)
- Remote deploy: [`chain-of-geths/deploy.sh`](chain-of-geths/deploy.sh)

### Quick start (remote deploy)

```bash
# Ensure SSH_KEY_PATH points at your PEM and SSH can reach the VM.
./chain-of-geths/deploy.sh
```

## Resurrection Project

GPU mining infrastructure to extend historical chains beyond their original blocks, reducing difficulty from ~62 TH to CPU-mineable levels (~10 MH).

Documentation: [`resurrection/README.md`](resurrection/README.md)

### Homestead Revival (Recommended)
- **Starting point**: Block 1,919,999 (pre-DAO fork)
- **Initial difficulty**: ~62 TH
- **Target difficulty**: ~10 MH (auto-stop for CPU handoff)
- **Time**: ~8 days with 8x RTX 3090
- **Cost**: ~$180 on Vast.ai

### Frontier Revival (Advanced)
- **Starting point**: Block 1,149,999 (pre-Homestead fork)
- **Initial difficulty**: ~17.5 TH
- **Target difficulty**: ~50 MH (auto-stop for CPU handoff)
- **Time**: ~4-6 months with 8x RTX 3090 (99x slower due to simpler difficulty algorithm)
- **Cost**: ~$3,000-4,000 on Vast.ai

Vast.ai deployment scripts:
- [`resurrection/vast-homestead/`](resurrection/vast-homestead/) - Homestead mining
- [`resurrection/vast-frontier/`](resurrection/vast-frontier/) - Frontier mining

## Infographic

Open [`infographic.html`](infographic.html) in a browser for a visual overview of the project architecture.
