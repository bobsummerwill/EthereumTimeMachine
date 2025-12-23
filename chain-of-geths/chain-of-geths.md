# Chain of Geths

This directory contains a Docker Compose stack that runs multiple Geth versions (plus Lighthouse) and wires them together via static peering.

Entrypoints:
- Compose stack: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml)
- Key/config generation: [`chain-of-geths/generate-keys.sh`](chain-of-geths/generate-keys.sh)
- Image build: [`chain-of-geths/build-images.sh`](chain-of-geths/build-images.sh)
- Remote deploy: [`chain-of-geths/deploy.sh`](chain-of-geths/deploy.sh)

## What we built

### Execution + consensus (top of chain)

- **`geth-v1-16-7`** (execution, `eth/68–69`) + **`lighthouse-16-7`** (consensus) track post-Merge mainnet.
  - Services: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml)
  - `geth-v1-16-7` exposes HTTP JSON-RPC on host port `8545`.

### Protocol bridge chain (down to Frontier)

The chain is wired so adjacent nodes share at least one `eth/*` subprotocol:

```
                           (post-Merge head)
            +-----------------------------------------------+
            | lighthouse-16-7 (v8.0.1, 20th Nov 2025) (CL)  |
            | geth-v1-16-7 (4th Nov 2025) (EL)              |
            | eth/68-69                                     |
            | Forks added:                                  |
            |   Cancun                                      |
            +-----------------------------------------------+
                               |
                               | (offline block export/import up to cutoff)
                               v
            +-----------------------------------------------+
            | geth-v1-11-6 (20th Apr 2023)                  |
            | eth/66-68                                     |
            | Forks added:                                  |
            |   Shanghai                                    |
            |   Paris (Merge)                               |
            |   Gray Glacier                                |
            |   Arrow Glacier                               |
            +-----------------------------------------------+
                               |
                               | eth/66
                               v
            +-----------------------------------------------+
            | geth-v1-10-0 (3rd Mar 2021)                   |
            | eth/64-66                                     |
            | Forks added:                                  |
            |   London                                      |
            |   Berlin                                      |
            +-----------------------------------------------+
                               |
                               | eth/64-65
                               v
            +-----------------------------------------------+
            | geth-v1-9-25 (11th Dec 2020)                  |
            | eth/63-65                                     |
            | Forks added:                                  |
            |   Muir Glacier                                |
            |   Istanbul                                    |
            |   Petersburg                                  |
            |   Constantinople                              |
            |   Byzantium                                   |
            |   Spurious Dragon                             |
            |   Tangerine Whistle                           |
            |   DAO                                         |
            +-----------------------------------------------+
                               |
                               | eth/63
                               v
            +-----------------------------------------------+
            | geth-v1-3-6 (1st Apr 2016)                    |
            | eth/61-63                                     |
            | Forks added:                                  |
            |   Homestead                                   |
            +-----------------------------------------------+
                               |
                               | eth/61
                               v
            +-----------------------------------------------+
            | geth-v1-0-3 (27th Jan 2014)                   |
            | eth/60-61                                     |
            | Forks:                                        |
            |   Frontier                                    |
            +-----------------------------------------------+
```

Services:
- `geth-v1-11-6`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:42) (line 42)
- `geth-v1-10-0`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:70) (line 70)
- `geth-v1-9-25`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:99) (line 99)
- `geth-v1-3-6`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:125) (line 125)
- `geth-v1-0-3`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:151) (line 151)

## Offline export/import seeding (bridge workflow)

The stack uses a single consensus client (`lighthouse-16-7`) for the head node.

The bridge workflow seeds older datadirs up to a fixed historical cutoff using **block export/import**:

1. Let `geth-v1-16-7` + `lighthouse-16-7` sync normally.
2. Export blocks `0..CUTOFF_BLOCK` from the modern node.
3. Import that block range into `geth-v1-11-6` (and then bring up the rest of the legacy chain).

Automation:
- Bridge seeding orchestration: [`chain-of-geths/seed-v1.11.6-when-ready.sh`](chain-of-geths/seed-v1.11.6-when-ready.sh)
- One-shot helper for fixed cutoff: [`chain-of-geths/seed-cutoff.sh`](chain-of-geths/seed-cutoff.sh)
- Export helper (RPC-based): [`chain-of-geths/seed-rlp-from-rpc.py`](chain-of-geths/seed-rlp-from-rpc.py)

This avoids the “old chainstate format” / “no compatible consensus client” problem: the modern EL+CL stays authoritative for head sync, while the legacy nodes consume only the historical block range we seeded.

## Static peering (no discovery for older nodes)

Older services run with discovery disabled and peer **only** to the next node in the chain.

`generate-keys.sh` writes deterministic peering/config files under `chain-of-geths/generated-files/`:
- `nodekey`
- `static-nodes.json`
- `config.toml` (newer nodes)
- `genesis.json` (v1.0.3)

See: [`chain-of-geths/generate-keys.sh`](chain-of-geths/generate-keys.sh)

This makes peering deterministic across restarts and across the AWS deployment.

## Monitoring

The stack includes Prometheus + Grafana + a JSON-RPC exporter so metrics work across old geth versions:

- Exporter: [`chain-of-geths/monitoring/exporter/app.py`](chain-of-geths/monitoring/exporter/app.py)
- Prometheus config: [`chain-of-geths/monitoring/prometheus/prometheus.yml`](chain-of-geths/monitoring/prometheus/prometheus.yml)
- Grafana dashboard provisioning: [`chain-of-geths/monitoring/grafana/provisioning/dashboards/dashboard.yml`](chain-of-geths/monitoring/grafana/provisioning/dashboards/dashboard.yml)
- Grafana dashboard JSON: [`chain-of-geths/monitoring/grafana/dashboards/chain-of-geths.json`](chain-of-geths/monitoring/grafana/dashboards/chain-of-geths.json)
- Minimal “Sync UI”: [`chain-of-geths/monitoring/sync-ui/server.js`](chain-of-geths/monitoring/sync-ui/server.js)


Endpoints (on the deployed host; see [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml)):
- Grafana: http://localhost:3000 (default `admin` / `admin`)
- Prometheus: http://localhost:9090
- Exporter metrics: http://localhost:9100/metrics
- Sync UI: http://localhost:8088

## Generated files directory

All generated material is under `chain-of-geths/generated-files/`.

[`.gitignore`](.gitignore) is configured to:
- ignore `known_hosts`, `jwtsecret`, exports/logs, docker image tarballs, and chain DB data
- allowlist `nodekey`, `static-nodes.json`, `config.toml`, and `genesis.json`

## Remote deploy

Run: [`chain-of-geths/deploy.sh`](chain-of-geths/deploy.sh)

## Deployment

Run the end-to-end automation from your machine:

- [`chain-of-geths/deploy.sh`](chain-of-geths/deploy.sh)

It:
1. Generates keys/static-nodes
2. Builds images
3. Copies artifacts + compose stack to the VM
4. Starts the modern head node + monitoring
5. Seeds the bridge via export/import (once)
6. Starts the legacy chain in stages
