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

### Protocol bridge chain (down to Frontier)

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
             | geth v1.3.6 (1st Apr 2016)                    |
             | eth/61-63                                     |
             | Forks supported:                              |
             |   Homestead                                   |
             |   Frontier                                    |
             +-----------------------------------------------+
                                  |
                                   | P2P eth/61 (protocol bridge)
                                   v
                  +-----------------------------------------------+
                  | geth v1.0.2 (22nd Aug 2015)                   |
                  | eth/60-61                                     |
                  | Forks supported:                              |
                  |   Frontier                                    |
                  +-----------------------------------------------+
  ```

Services:
- `geth-v1-16-7`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml)
- `lighthouse-v8-0-1`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml)
- `geth-v1-11-6`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml)
- `geth-v1-10-8`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml)
- `geth-v1-9-25`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml)
- `geth-v1-3-6`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml)
- `geth-v1-0-2`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml)
- `geth-exporter`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml)
- `prometheus`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml)
- `sync-ui`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml)
- `grafana`: [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml)

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


This avoids the "old chainstate format" / "no compatible consensus client" problem: the modern EL+CL stays authoritative for head sync, while the legacy nodes consume only the historical block range we seeded.

## Why RLP export/import instead of P2P sync?

### The Post-Merge Consensus Client Requirement

After The Merge (Paris hard fork, Sep 2022), Ethereum execution clients like Geth **cannot sync or progress without a paired consensus client** (beacon node). The consensus client tells the execution client which chain is canonical via the Engine API.

This creates a fundamental problem for our bridge chain:

```
Pre-Merge:   Execution client syncs independently via P2P
Post-Merge:  Execution client REQUIRES consensus client to sync ANY blocks
```

**Geth v1.11.6** is a post-Merge client. Even though we only need it to sync pre-Merge historical blocks, it still requires a consensus client to progress at all.

### Failed Attempts to Pair Consensus Clients

We extensively tried to pair a consensus client with Geth v1.11.6:

#### Attempt 1: Modern Lighthouse (v8.0.1)
- **Problem**: Lighthouse v8.0.1 expects SSZ format from post-Deneb era
- **Result**: Incompatible with Geth v1.11.6's Engine API expectations

#### Attempt 2: Old Lighthouse (v4.5.0, v4.6.0)
- **Problem**: Requires checkpoint sync to avoid impractical genesis sync
- **Result**: Checkpoint sync endpoints only serve current SSZ format data

#### Attempt 3: Prysm (various versions)
- **Problem**: Same SSZ format incompatibility
- **Additional**: DNS resolution issues with checkpoint sync URLs
- **Result**: Could not complete checkpoint sync

#### Attempt 4: Syncing from Genesis
- **Problem**: Beacon chain genesis sync takes weeks/months
- **Result**: Impractical for our use case

### The SSZ Format Problem

The core issue is **SSZ (Simple Serialize) format evolution**. The BeaconState structure has changed through multiple hard forks:

| Fork | SSZ Changes |
|------|-------------|
| Altair | Added sync committees |
| Bellatrix | Added execution payload fields |
| Capella | Added withdrawal fields |
| Deneb | Added blob sidecar fields |

**Checkpoint sync requires downloading a finalized BeaconState** from a checkpoint endpoint. All public checkpoint endpoints serve the **current** SSZ format (post-Deneb). Old consensus client versions expect **old** SSZ formats.

```
Checkpoint Endpoint (2024+) ──► Current SSZ format (Deneb+)
                                      │
                                      ▼
Old Lighthouse v4.6.0 ──────► Expects pre-Deneb SSZ format
                                      │
                                      ▼
                              ❌ FORMAT MISMATCH
```

No public source of historical BeaconState data in old SSZ formats exists. ERA archive files preserve historical data but still require a compatible consensus client to read them.

### The Solution: Bypass Consensus Entirely

RLP export/import elegantly sidesteps this entire problem:

1. **Modern stack syncs normally**: `geth-v1-16-7` + `lighthouse-v8-0-1` sync mainnet with full consensus
2. **Export blocks as raw data**: `geth export` writes RLP-encoded blocks to a file
3. **Import into legacy client**: `geth import` loads blocks directly, no consensus required
4. **Legacy chain syncs via P2P**: v1.10.8 and older sync from v1.11.6 using pre-Merge P2P protocols

```
Modern EL+CL          RLP Export           Legacy EL (no CL)
┌─────────────┐       ┌─────────┐         ┌─────────────┐
│ geth v1.16.7│──────►│ blocks  │────────►│ geth v1.11.6│
│ lighthouse  │       │ 0..1.9M │         │ (standalone)│
└─────────────┘       └─────────┘         └─────────────┘
       │                                         │
   Full Merge                              No consensus
   consensus                               client needed
```

The offline transfer treats blocks as pure historical data rather than requiring live consensus validation. This is the **only viable approach** given the current state of Ethereum tooling.

## Static peering (no discovery for older nodes)

Older services run with discovery disabled and peer **only** to the next node in the chain for protocol bridging.

Offline-seeded node:
- `geth-v1-11-6` is populated by import from the `geth-v1-16-7` export.

`generate-keys.sh` writes deterministic peering/config files under `chain-of-geths/generated-files/`:
- `nodekey`
- `static-nodes.json`
- `config.toml` (newer nodes)

See: [`chain-of-geths/generate-keys.sh`](chain-of-geths/generate-keys.sh)

This makes peering deterministic across restarts and across the AWS deployment.

## Monitoring

The stack includes Prometheus + Grafana + a JSON-RPC exporter so metrics work across old geth versions:

- Exporter: [`chain-of-geths/monitoring/exporter/app.py`](chain-of-geths/monitoring/exporter/app.py)
- Prometheus config: [`chain-of-geths/monitoring/prometheus/prometheus.yml`](chain-of-geths/monitoring/prometheus/prometheus.yml)
- Grafana dashboard provisioning: [`chain-of-geths/monitoring/grafana/provisioning/dashboards/dashboard.yml`](chain-of-geths/monitoring/grafana/provisioning/dashboards/dashboard.yml)
- Grafana dashboard JSON: [`chain-of-geths/monitoring/grafana/dashboards/chain-of-geths.json`](chain-of-geths/monitoring/grafana/dashboards/chain-of-geths.json)
- Minimal “Sync UI”: [`chain-of-geths/monitoring/sync-ui/server.js`](chain-of-geths/monitoring/sync-ui/server.js)


Endpoints (on the Ubuntu VM running the stack; `VM_IP` defaults come from [`chain-of-geths/.env.example`](chain-of-geths/.env.example:1) and can be overridden in `chain-of-geths/.env` (gitignored)):
- Grafana: http://<VM_IP>:3000 (default `admin` / `admin`)
- Prometheus: http://<VM_IP>:9090
- Exporter metrics: http://<VM_IP>:9100/metrics
- Sync UI: http://<VM_IP>:8088

## AWS remote VM setup (EC2)

One working reference setup:

- Instance type: **m6a.2xlarge**
- AMI: **Ubuntu 24.04 LTS**
- Disk: **1500 GB** (EBS)

### Security Group inbound rules

Minimum recommended inbound rules (lock these down to your IP/CIDR where possible):

- SSH (for [`chain-of-geths/deploy.sh`](chain-of-geths/deploy.sh))
  - TCP 22

Monitoring UIs (optional, but commonly used):

- Grafana UI
  - TCP 3000
- Sync UI
  - TCP 8088

External P2P peering (required if you want a non-VM node, e.g. the Windows zip bundle, to dial the VM):

- `geth-v1-3-6` P2P
  - TCP 30311
  - UDP 30311
  - This corresponds to the host port publishing in [`geth-v1-3-6.ports`](chain-of-geths/docker-compose.yml:182)

Notes:

- Generated `static-nodes.json` uses **docker-compose service names** (e.g. `geth-v1-3-6`) rather than fixed container IPs.
  This keeps static peering stable even when docker assigns different IPs on restart.
- External machines must use the VM’s public IP/DNS, plus the published host ports (container DNS names are not resolvable outside Docker).
- On a default Ubuntu EC2, `ufw` is usually **inactive**. If you enabled it, you must also allow the same inbound ports at the VM firewall.

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

## Required hacks/workarounds (and why they exist)

- Offline export/import for `v1.11.6`: no consensus client exists that both speaks the Engine API `v1.11.x` expects and can checkpoint-sync from today’s Deneb/Cancun BeaconStates. We seed `v1.11.6` from `v1.16.7` RLP export up to a cutoff instead of P2P/CL sync.
- Disable trusted checkpoint in `v1.10.8`: unpatched 1.10.x demands snap pivot headers (~12.9M) the truncated bridge will never have. We set the checkpoint to nil so it can sync only the seeded range from `v1.11.6`.
- Force full sync, no snap/fast on legacy nodes: `v1.10.8`/`v1.9.25` use `--snapshot=false --syncmode full`; `v1.3.6` uses `--fast=false`. Prevents pivot/state downloads beyond the cutoff their upstream can serve.
- Static identities/peering: pre-generated nodekeys/enodes, fixed Docker bridge IPs, discovery disabled on legacy nodes. Keeps very old clients peered despite DNS/protocol gaps.
- Watchdog + staged startup with resets: entrypoint watchdog restarts stalled nodes; `start-legacy-staged.sh` gates downstream startup until upstream serves blocks and can wipe downstream chaindata if stuck/ahead, avoiding latch-at-genesis/ahead-of-upstream deadlocks.
- Monitoring shortcuts: custom JSON-RPC exporter (not Geth metrics) for old versions, synthetic export/import rows, and gating `v1.11.6` progress until seeding is done.
- Build/runtime tweaks for old binaries: `v1.0.2` built with Go 1.4 on Debian jessie archive; `v1.3.6` download with fallback extraction; `v1.10.8` patched. Some artifacts lack upstream checksums.
- Lab-facing defaults: HTTP/RPC bound to `0.0.0.0` for monitoring and remote deploy scripts with hardcoded defaults/volume wipes; lock down before any exposed deployment.

### Base images we use (and why)

- **Debian jessie (build stage only for v1.0.2)**: Go 1.4’s cgo parser breaks on newer binutils/DWARF. Jessie’s GCC 4.9 keeps the v1.0.2 build stable; runtime is not jessie.
- **Debian bullseye-slim (most Geth runtimes; v1.10.8 build stage; 1.9.25/1.11.6 binaries)**: A stable floor that matches the era of the shipped tarballs and upstream build targets. Newer bookworm is possible for self-built binaries, but tarball-based runtimes are safer on bullseye.
- **python:3.12-slim**: Debian-based (bookworm-era) slim image for the exporter; small and current Python.
- **node:22-alpine**: Alpine for the sync UI to keep the Node runtime small; no native deps expected.

If you want to upgrade to bookworm universally, rebuild the Geth binaries on it and validate runtime. Tarball-based images (1.9.25/1.11.6) should stay on bullseye unless rebuilt. Jessie remains required only for the v1.0.2 build toolchain.
