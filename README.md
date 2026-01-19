# EthereumTimeMachine

Tools to run historical Ethereum clients and related workflows.

## Overview

The Ethereum Time Machine project enables running authentic historical Ethereum software on contemporary hardware. It consists of three phases:

1. **Chain of Geths** - Protocol bridge infrastructure to sync historical chaindata
2. **Resurrection** - GPU mining to extend historical chains to CPU-mineable difficulty
3. **Running Mist** - Authentic Mist wallet experience on historical chains

## Chain of Geths

A Docker Compose stack of multiple Geth versions (plus Lighthouse) where adjacent nodes share overlapping `eth/*` subprotocols, enabling modern clients to sync historical chaindata to ancient Geth versions.

See [`chain-of-geths/README.md`](chain-of-geths/README.md)

## Resurrection

GPU mining to crash difficulty from 62.38 TH to CPU-mineable levels.

| Option | Time | Cost | Blocks |
|--------|------|------|--------|
| **Homestead** (recommended) | ~8 days | ~$180 | ~320 |
| Frontier | ~19 months | ~$14,000 | ~26,500 |

See [`resurrection/README.md`](resurrection/README.md)

## Running Mist

Run the original Mist wallet against historical Geth versions via IPC.

| Geth | Mist | Era |
|------|------|-----|
| v1.1.0 | v0.2.6 | Frontier |
| v1.3.6 | v0.7.4 | Homestead |

See [`running-mist/README.md`](running-mist/README.md)

## Infographic

Open [`infographic.html`](infographic.html) in a browser for a visual overview.
