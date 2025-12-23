# Chain of Geths (implemented)

This document describes the **current, working** “Chain of Geths” implementation in this repository (not a future plan).

The system is defined by:
- Docker Compose: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:1)
- Key/static-peering generator: [`chain-of-geths/generate-keys.sh`](chain-of-geths/generate-keys.sh:1)
- Image builder (downloads binaries + builds v1.0.3 from source): [`chain-of-geths/build-images.sh`](chain-of-geths/build-images.sh:1)
- Automated deploy to the AWS VM: [`chain-of-geths/deploy.sh`](chain-of-geths/deploy.sh:1)

## What we built

### Execution + consensus (top of chain)

- **`geth-v1-16-7`** (execution, `eth/68–69`) + **`lighthouse-16-7`** (consensus) track post-Merge mainnet.
  - Services: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:4)
  - `geth-v1-16-7` exposes HTTP JSON-RPC on host port `8545`.

### Protocol bridge chain (down to Frontier)

The chain is wired so adjacent nodes share at least one `eth/*` subprotocol:

```
                           (post-Merge head)
           +----------------------------------------------+
           | lighthouse-16-7 (CL) + geth-v1-16-7 (EL)      |
           | eth/68-69                                     |
           | Forks added:                                  |
           |   Cancun                                      |
           +----------------------------------------------+
                               |
                               | (offline block export/import up to cutoff)
                               v
           +----------------------------------------------+
           | geth-v1-11-6                                  |
           | eth/66-68                                     |
           | Forks added:                                  |
           |   Merge                                       |
           |   Shanghai                                    |
           +----------------------------------------------+
                               |
                               | eth/66
                               v
           +----------------------------------------------+
           | geth-v1-10-0                                  |
           | eth/64-66                                     |
           | Forks added:                                  |
           |   Berlin                                      |
           |   London                                      |
           +----------------------------------------------+
                               |
                               | eth/64-65
                               v
           +----------------------------------------------+
           | geth-v1-9-25                                  |
           | eth/63-65                                     |
           | Forks added:                                  |
           |   DAO                                         |
           |   Byzantium                                   |
           |   Constantinople                              |
           |   Istanbul                                    |
           +----------------------------------------------+
                               |
                               | eth/63
                               v
           +----------------------------------------------+
           | geth-v1-3-6                                   |
           | eth/61-63                                     |
           | Forks added:                                  |
           |   Homestead                                   |
           +----------------------------------------------+
                               |
                               | eth/61
                               v
           +----------------------------------------------+
           | geth-v1-0-3                                   |
           | eth/60-61                                     |
           | Forks added:                                  |
           |   Frontier                                    |
           +----------------------------------------------+
```

Services:
- `geth-v1-11-6`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:42)
- `geth-v1-10-0`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:70)
- `geth-v1-9-25`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:99)
- `geth-v1-3-6`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:125)
- `geth-v1-0-3`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:151)

## The key workaround: offline export/import seeding (no “old EL + CL” pair)

We do **not** run a second beacon node for older execution clients.

Instead, we seed the bridge datadirs up to a fixed historical cutoff using **block export/import**:

1. Let `geth-v1-16-7` + `lighthouse-16-7` sync normally.
2. Export blocks `0..CUTOFF_BLOCK` from the modern node.
3. Import that block range into `geth-v1-11-6` (and then bring up the rest of the legacy chain).

Automation:
- Bridge seeding orchestration: [`chain-of-geths/seed-v1.11.6-when-ready.sh`](chain-of-geths/seed-v1.11.6-when-ready.sh:1)
- One-shot helper for fixed cutoff: [`chain-of-geths/seed-cutoff.sh`](chain-of-geths/seed-cutoff.sh:1)
- Export helper (RPC-based): [`chain-of-geths/seed-rlp-from-rpc.py`](chain-of-geths/seed-rlp-from-rpc.py:1)

This avoids the “old chainstate format” / “no compatible consensus client” problem: the modern EL+CL stays authoritative for head sync, while the legacy nodes consume only the historical block range we seeded.

## Static peering (no discovery for legacy nodes)

Legacy services run with discovery disabled and peer **only** to the next node in the chain.

- `generate-keys.sh` pre-generates node keys and writes `static-nodes.json` into each datadir under `chain-of-geths/output/`.
  - Script: [`chain-of-geths/generate-keys.sh`](chain-of-geths/generate-keys.sh:1)

This makes peering deterministic across restarts and across the AWS deployment.

## Monitoring

The stack includes Prometheus + Grafana + a JSON-RPC exporter so metrics work across old geth versions:

- Exporter: [`chain-of-geths/monitoring/exporter/app.py`](chain-of-geths/monitoring/exporter/app.py:1)
- Prometheus config: [`chain-of-geths/monitoring/prometheus/prometheus.yml`](chain-of-geths/monitoring/prometheus/prometheus.yml:1)
- Grafana dashboard provisioning: [`chain-of-geths/monitoring/grafana/provisioning/dashboards/dashboard.yml`](chain-of-geths/monitoring/grafana/provisioning/dashboards/dashboard.yml:1)
- Grafana dashboard JSON: [`chain-of-geths/monitoring/grafana/dashboards/chain-of-geths.json`](chain-of-geths/monitoring/grafana/dashboards/chain-of-geths.json:1)
- Minimal “Sync UI”: [`chain-of-geths/monitoring/sync-ui/server.js`](chain-of-geths/monitoring/sync-ui/server.js:1)

## Deployment

Run the end-to-end automation from your machine:

- [`chain-of-geths/deploy.sh`](chain-of-geths/deploy.sh:1)

It:
1. Generates keys/static-nodes
2. Builds images
3. Copies artifacts + compose stack to the VM
4. Starts the modern head node + monitoring
5. Seeds the bridge via export/import (once)
6. Starts the legacy chain in stages
