# Chain of Geths

This directory contains a Docker Compose stack that runs multiple Geth versions (plus Lighthouse) and wires them together via a mix of static peering and offline export/import seeding.

Entrypoints:
- Compose stack: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml)
- Key/config generation: [`chain-of-geths/generate-keys.sh`](chain-of-geths/generate-keys.sh)
- Image build: [`chain-of-geths/build-images.sh`](chain-of-geths/build-images.sh)
- Remote deploy: [`chain-of-geths/deploy.sh`](chain-of-geths/deploy.sh)

## What we built

### Execution + consensus (top of chain)

- **`geth-v1-16-7`** (execution, `eth/68–69`) + **`lighthouse-v8-0-1`** (consensus) track post-Merge mainnet.
  - Services: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml)
  - `geth-v1-16-7` exposes HTTP JSON-RPC on host port `8545`.

### Protocol bridge chain (down to Homestead)

The chain is wired so adjacent nodes share at least one `eth/*` subprotocol:
  
  ```
                    Ethereum mainnet P2P (discovery + bootnodes)
                                |
                                v
                            (post-Merge head)
            +-----------------------------------------------+
            | lighthouse v8.0.1 (20th Nov 2025) (CL)        |
            | geth v1.16.7 (4th Nov 2025) (EL)              |
            | eth/68-69                                     |
            | Forks added:                                  |
            |   Cancun                                      |
            +-----------------------------------------------+
                                |
                                | (offline RLP export/import up to cutoff)
                                v
            +-----------------------------------------------+
            | geth v1.11.6 (20th Apr 2023)                  |
            | eth/66-68                                     |
            | Forks added:                                  |
            |   Shanghai                                    |
            |   Paris (Merge)                               |
            |   Gray Glacier                                |
            |   Arrow Glacier                               |
            +-----------------------------------------------+
                                |
                                | P2P eth/66 (protocol bridge)
                                v
            +-----------------------------------------------+
            | geth v1.10.8 (21st Sep 2021)                  |
            | eth/65-66                                     |
            | Forks added:                                  |
            |   London                                      |
            |   Berlin                                      |
            +-----------------------------------------------+
                                |
                                | P2P eth/65 (protocol bridge)
                                v
            +-----------------------------------------------+
            | geth v1.9.25 (11th Dec 2020)                  |
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
                                | P2P eth/63 (protocol bridge)
                                v
             +-----------------------------------------------+
             | geth v1.3.3 (5th Jan 2016)                    |
             | eth/61-63                                     |
             | Forks supported:                              |
             |   Homestead                                   |
             |   Frontier                                    |
              +-------------------------------------------- -+
```

Services:
- `geth-v1-16-7`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:4)
- `lighthouse-v8-0-1`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:198)
- `geth-v1-11-6`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:46)
- `geth-v1-10-8`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:78)
- `geth-v1-9-25`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:110)
- `geth-v1-3-3`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:140)
- `geth-exporter`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:232)
- `prometheus`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:263)
- `sync-ui`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:280)
- `grafana`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:294)

## Offline export/import seeding (bridge workflow)

The stack uses a single consensus client (`lighthouse-v8-0-1`) for the head node.

The bridge workflow seeds the post-Merge-incompatible execution client (v1.11.6) up to a fixed historical cutoff using **RLP block export/import**.

1. Let `geth-v1-16-7` + `lighthouse-v8-0-1` sync normally.
2. Export blocks `0..CUTOFF_BLOCK` from `geth-v1-16-7`.
3. Import that block range into `geth-v1-11-6`.
4. Start the downstream legacy nodes; they sync via normal P2P from their upstream bridge peers (static peering).

Automation:
- Bridge seeding orchestration: [`chain-of-geths/seed-v1.11.6-when-ready.sh`](chain-of-geths/seed-v1.11.6-when-ready.sh)
- One-shot helper for fixed cutoff: [`chain-of-geths/seed-cutoff.sh`](chain-of-geths/seed-cutoff.sh)


This avoids the “old chainstate format” / “no compatible consensus client” problem: the modern EL+CL stays authoritative for head sync, while the legacy nodes consume only the historical block range we seeded.

## Static peering (no discovery for older nodes)

Older services run with discovery disabled and peer **only** to the next node in the chain for protocol bridging.

Offline-seeded node:
- `geth-v1-11-6` is populated by import from the `geth-v1-16-7` export.

`generate-keys.sh` writes deterministic peering/config files under `chain-of-geths/generated-files/`:
- `nodekey`
- `static-nodes.json`
- `config.toml` (newer nodes)
- (no genesis.json needed for this chain)

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
Endpoints (on the Ubuntu VM running the stack; default `VM_IP` is in [`chain-of-geths/deploy.sh`](chain-of-geths/deploy.sh:39) (line 39)):
- Grafana: http://<VM_IP>:3000 (default `admin` / `admin`)
- Prometheus: http://<VM_IP>:9090
- Exporter metrics: http://<VM_IP>:9100/metrics
- Sync UI: http://<VM_IP>:8088

## Generated files directory

All generated material is under `chain-of-geths/generated-files/`.

[`.gitignore`](.gitignore) is configured to:
- ignore `known_hosts`, `jwtsecret`, exports/logs, docker image tarballs, and chain DB data
- allowlist `nodekey`, `static-nodes.json`, `config.toml`, and `genesis.json`

## Remote deploy

Run: [`chain-of-geths/deploy.sh`](chain-of-geths/deploy.sh)

This script:
1. Generates keys/static-nodes
2. Builds images
3. Copies artifacts + compose stack to the VM
4. Starts the head node + monitoring
5. Seeds the bridge via export/import (once)
6. Starts the legacy runner (brings up the rest of the chain)
