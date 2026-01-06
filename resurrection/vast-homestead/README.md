# Vast.ai Homestead Chain Extender (from block 1,919,999)

This folder provides a **single-container** chain extension setup intended for **Vast.ai**:

- `geth` **v1.3.6** (Homestead-era)
- a **user-supplied GPU miner** command pointed at geth's **getwork** API (`eth_getWork` / `eth_submitWork`)

This is meant to extend a **pre-DAO** chain tip at **1,919,999** (the default cutoff used by the bridge stack in [`chain-of-geths/docker-compose.yml`](chain-of-geths/docker-compose.yml:49)).

## What you provide

You said you'll have a tarball containing the geth datadir.

## Deterministic identity + miner account (generated-files)

Run [`resurrection/vast-homestead/generate-identity.sh`](resurrection/vast-homestead/generate-identity.sh:1).

### Config via `.env`

Yes: put `IDENTITY_SEED=...` in `resurrection/vast-homestead/.env`.

- `docker compose` automatically reads `.env` from the same directory as [`resurrection/vast-homestead/docker-compose.yml`](resurrection/vast-homestead/docker-compose.yml:1).
- [`resurrection/vast-homestead/generate-identity.sh`](resurrection/vast-homestead/generate-identity.sh:1) will also auto-create and source `.env` (copied from `.env.example`) so the same config drives both identity generation and runtime.

Template: [`resurrection/vast-homestead/.env.example`](resurrection/vast-homestead/.env.example:1).

This creates a `generated-files/` tree containing:
- `generated-files/data/v1.3.6/nodekey` (stable node identity)
- `generated-files/data/v1.3.6/keystore/*` (miner account)
- `generated-files/miner-password.txt` (used to unlock the miner account)
- `generated-files/miner-address.txt` (mining coinbase)

You can override determinism inputs with:
- `IDENTITY_SEED=...` (changes nodekey + miner key)
- `MINER_PASSWORD=...` (changes keystore encryption password)

Example:

```bash
cd resurrection/vast-homestead
IDENTITY_SEED='my-homestead-net-1' MINER_PASSWORD='dev' ./generate-identity.sh
```

### Expected tar layout

The container extracts the tar into `/data` if `/data` is empty.

For `geth` v1.3.6, the simplest working layout is:

```
chaindata/
dapp/
keystore/   (optional)
nodekey     (optional)
static-nodes.json (optional)
...
```

If your tar has an extra top-level directory (e.g. `v1.3.6/chaindata/...`), the entrypoint will try to unwrap it.

## Miner note (why we don’t ship one in the image)

The classic open-source Ethash miner (`ethminer`) is archived and its build relies on Hunter downloading Boost from Bintray (dead), so baking a portable CUDA miner into this repo is fragile.

Instead, this container runs geth and executes whatever miner you provide via `MINER_CMD` (mounted into the container).

If you prefer, there is also a **second container** that builds and runs **Genoil’s cpp-ethereum ethminer**.

- Build stage: **Ubuntu 14.04** (2015-era toolchain expectation)
- Runtime stage: modern CUDA runtime

See: [`resurrection/vast-homestead/docker-compose.yml`](resurrection/vast-homestead/docker-compose.yml:1) and [`resurrection/vast-homestead/miner-genoil/Dockerfile`](resurrection/vast-homestead/miner-genoil/Dockerfile:1).

## Running on Vast.ai (typical workflow)

1. Run [`resurrection/vast-homestead/generate-identity.sh`](resurrection/vast-homestead/generate-identity.sh:1).
2. Put your chain tarball at `./generated-files/input/chaindata.tar`.
3. Build and run with docker-compose (recommended):

```bash
docker compose up --build
```

Security note: do **not** expose `8545` publicly. If you need remote access, use an SSH tunnel.

## Local test via docker-compose

Drop your tar at `./generated-files/input/chaindata.tar` and run:

```bash
docker compose up --build
```

This will start:
- `geth` (v1.3.6) as `vast-homestead-geth`
- `genoil-ethminer` as `vast-homestead-genoil-ethminer`

## Timestamp strategy (no waiting)

You said you don’t want to actually wait 20 minutes between blocks. The default setup instead **lies about time** with a per-block step:

- On startup it reads the **latest block timestamp** from your imported datadir.
- It then sets fake time to **(latest_timestamp + 1200 seconds)** and mines **exactly one block**.
- After the block is mined, it restarts geth with fake time set to **(new_latest_timestamp + 1200 seconds)**.

This produces **~20 minutes of timestamp delta per mined block** without real waiting.

Default config is in [`geth.environment`](resurrection/vast-homestead/docker-compose.yml:1) and implemented by:
- [`resurrection/vast-homestead/entrypoint.sh`](resurrection/vast-homestead/entrypoint.sh:1)
- [`resurrection/vast-homestead/geth_time_stepper.py`](resurrection/vast-homestead/geth_time_stepper.py:1)

Notes:
- If `libfaketime` doesn’t work with the Go 1.6 geth binary on a given host, you can fall back to the miner-side pause controller (`PAUSE_BETWEEN_BLOCKS_SECONDS`) using [`resurrection/vast-homestead/mining_controller.py`](resurrection/vast-homestead/mining_controller.py:1).

## Why geth v1.3.6?

The chain-of-geths bridge includes `geth v1.3.6` as the Homestead-era endpoint (see [`chain-of-geths/README.md`](chain-of-geths/README.md:76)). This setup is intentionally isolated (`--nodiscover`, `--maxpeers 0`) so you don't accidentally join real mainnet while mining a historical fork.
