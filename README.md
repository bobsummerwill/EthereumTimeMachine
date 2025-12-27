# EthereumTimeMachine
Tools to run historical Ethereum clients and related workflows.

## Chain of Geths

The primary implementation in this repo is **Chain of Geths**: a Docker Compose stack of multiple Geth versions (plus Lighthouse) where adjacent nodes share overlapping `eth/*` subprotocols.

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

Reference: [`chain-of-geths/deploy.sh`](chain-of-geths/deploy.sh)
