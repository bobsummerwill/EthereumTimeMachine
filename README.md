# EthereumTimeMachine
Tools to revive Ethereum Frontier and Homestead chains

## Chain of Geths

This repository currently focuses on the **"Chain of Geths"** approach: run multiple historical Geth versions that share overlapping `eth/*` protocol versions, allowing a modern node to sync from mainnet and propagate chain data down to progressively older clients.

Start here:
- Design/plan: `chain-of-geths/chain-of-geths.md`
- Docker Compose stack (v1.16.7 → v1.3.6, with protocol bridge nodes): `chain-of-geths/docker-compose.yml`
- Automation scripts: `chain-of-geths/generate-keys.sh`, `chain-of-geths/build-images.sh`, `chain-of-geths/deploy.sh`

Note: The Docker Compose stack includes a containerized **Geth v1.0.3** (built from source).

## Visual sync progress (Grafana)

The Compose stack includes Prometheus + Grafana and a small JSON-RPC exporter.

- Grafana: http://localhost:3000 (default `admin` / `admin`) via [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:1)
- Prometheus: http://localhost:9090
- Exporter metrics: http://localhost:9100/metrics

The pre-provisioned dashboard is **“Chain of Geths – Sync Progress”**, with panels for:
- block height per node
- lag vs the top node (v1.16.7)
- remaining blocks while syncing
- peer count

## Generated artifacts

[`chain-of-geths/generate-keys.sh`](chain-of-geths/generate-keys.sh:1) writes its outputs under `chain-of-geths/output/` (ignored by git via [`.gitignore`](.gitignore:1)).

Example outputs:
- [`chain-of-geths/output/data/v1.10.0/static-nodes.json`](chain-of-geths/output/data/v1.10.0/static-nodes.json:1)
