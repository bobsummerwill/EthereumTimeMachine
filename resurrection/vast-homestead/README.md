# Vast.ai Homestead Chain Extender (from block 1,919,999)

This folder provides a **docker-compose** setup for crashing Homestead-era difficulty on **Vast.ai** GPU instances:

- `geth` **v1.3.6** (Homestead-era) with `libfaketime` for timestamp manipulation
- `ethminer` (Genoil) for GPU mining via getwork API

## Goal

Reduce difficulty from **~62 TH** (DAO fork) to **~10 MH** (CPU-mineable) by mining ~320 blocks with manipulated timestamps (20-minute gaps trigger maximum difficulty reduction per EIP-2).

The script auto-stops at 10 MH and keeps geth running for P2P sync, enabling CPU mining handoff to other machines.

## Time & Cost Estimates

| GPU Config | Hashrate | Time | Cost |
|------------|----------|------|------|
| 1x RTX 3090 | 105 MH/s | ~60 days | ~$1,440 |
| 4x RTX 3090 | 420 MH/s | ~15 days | ~$360 |
| **8x RTX 3090** | **846 MH/s** | **~8 days** | **~$180** |

Recommendation: **8x RTX 3090** (~$1/hr on Vast.ai) for fastest completion at lowest cost.

## How It Works

### The Difficulty Crash Algorithm (EIP-2)

```
adjustment = max(1 - (timestamp_delta // 10), -99)
new_difficulty = parent_difficulty + (parent_difficulty // 2048) * adjustment
```

With a 20-minute (1200s) timestamp gap:
- `adjustment = max(1 - 120, -99) = -99`
- Each block reduces difficulty by ~4.83%
- ~320 blocks to crash from 62 TH to 10 MH

### Timestamp Manipulation

Instead of waiting 20 minutes between blocks, we use `libfaketime` to lie about the system time. Geth uses the system clock to propose block timestamps, so:

1. Read latest block timestamp from chain
2. Set fake time to `latest_timestamp + 1200s`
3. Mine one block (geth proposes timestamp = fake "now")
4. Repeat

This is handled automatically by `geth_time_stepper.py`.

## Prerequisites

1. **Chaindata tarball** (~27GB) exported from chain-of-geths v1.3.6 node at block 1,919,999

## Setup

### 1. Generate Deterministic Identity

```bash
cd resurrection/vast-homestead
./generate-identity.sh
```

This creates `generated-files/` with:
- `data/v1.3.6/nodekey` (stable node identity)
- `data/v1.3.6/keystore/*` (miner account)
- `miner-password.txt` (unlock password)
- `miner-address.txt` (mining coinbase)

Override with environment variables:
```bash
IDENTITY_SEED='my-homestead-net-1' MINER_PASSWORD='dev' ./generate-identity.sh
```

### 2. Prepare Chaindata

Place chaindata tarball at `./generated-files/input/chaindata.tar.gz` or set `CHAIN_DATA_TAR` in `.env`.

Expected tar layout:
```
chaindata/
dapp/
keystore/   (optional)
nodekey     (optional)
```

## Mining Software

The setup includes **Genoil's cpp-ethereum ethminer** in a separate container:
- Build stage: Ubuntu 14.04 (2015-era toolchain)
- Runtime: Modern CUDA runtime
- Uses getwork RPC API (`eth_getWork` / `eth_submitWork`)

See: `docker-compose.yml` and `miner-genoil/Dockerfile`.

## Vast.ai Deployment

### Quick Start

```bash
# 1. Search for 8x RTX 3090 instances
vastai search offers 'num_gpus=8 gpu_name=RTX_3090 inet_down>100' -o 'dph'

# 2. Create instance
vastai create instance OFFER_ID --image nvidia/cuda:11.8.0-devel-ubuntu22.04

# 3. Get SSH details
vastai show instance INSTANCE_ID

# 4. Upload chaindata (~27GB, ~6-7 hours)
rsync -avzP chaindata.tar.gz root@sshX.vast.ai:/root/ -e "ssh -p PORT"

# 5. Upload this folder
rsync -avzP resurrection/vast-homestead/ root@sshX.vast.ai:/root/vast-homestead/ -e "ssh -p PORT"

# 6. Start mining
ssh -p PORT root@sshX.vast.ai "cd /root/vast-homestead && docker compose up --build -d"
```

### Automation Script

Use `overnight-mining-automation.sh` for hands-off operation:
- Handles chaindata upload
- Starts docker-compose
- Monitors progress
- Logs to `overnight-mining.log`

### Monitoring

```bash
# Watch geth logs
ssh -p PORT root@sshX.vast.ai "docker logs -f vast-homestead-geth"

# Check current block number
ssh -p PORT root@sshX.vast.ai 'curl -s -X POST -H "Content-Type: application/json" \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}" \
  http://localhost:8545'

# Check difficulty
ssh -p PORT root@sshX.vast.ai 'curl -s -X POST -H "Content-Type: application/json" \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"latest\",false],\"id\":1}" \
  http://localhost:8545 | jq .result.difficulty'
```

### GPU Mining on Bare Metal (non-Docker)

If you prefer to run the standalone `vast-mining.sh` on a Vast instance and mine directly with GPUs (no CPU mining):

1. Build a current OpenCL-only ethminer (avoids CUDA crashes on Ampere): `./install-ethminer-opencl.sh`
2. Start mining (external ethminer only):
   ```bash
   ./vast-mining.sh
   ```
   Logs: `mining.log` (geth/script) and `/root/ethminer.log` (ethminer).

## Local Testing

```bash
docker compose up --build
```

Starts:
- `vast-homestead-geth` - Geth v1.3.6 with libfaketime
- `vast-homestead-genoil-ethminer` - GPU miner

Security: Do **not** expose port 8545 publicly. Use SSH tunnels for remote access.

## Key Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Main orchestration |
| `entrypoint.sh` | Geth container startup |
| `geth_time_stepper.py` | Advances fake time after each block |
| `mining_controller.py` | Alternative pause-based time control |
| `generate-identity.sh` | Creates deterministic node/miner keys |
| `overnight-mining-automation.sh` | Hands-off Vast.ai deployment |
| `install-ethminer-opencl.sh` | Builds OpenCL-only ethminer for Ampere GPUs (Vast bare-metal) |
| `vast-mining.sh` | Single-host Vast GPU script (8 GPUs, auto-stop at 10 MH for CPU handoff) |

## vast-mining.sh Features

The standalone `vast-mining.sh` script provides:
- **8 GPU mining** throughout (no tapering for fastest completion)
- **Auto-stop at 10 MH** difficulty threshold
- **P2P handoff mode**: When stopped, restarts geth with peers enabled for chaindata sync
- **Automatic restart** of geth/ethminer if they crash

### CPU Mining After Handoff

Once GPU mining auto-stops at 10 MH:
1. Geth keeps running with P2P enabled
2. Connect other nodes to sync the extended chaindata
3. Start CPU mining on those nodes (~500 KH/s)
4. First CPU block takes ~20 seconds, then accelerates rapidly
5. After ~50 blocks, mining is essentially instant

## Why Geth v1.3.6?

The chain-of-geths bridge uses `geth v1.3.6` as the Homestead-era endpoint. This setup is intentionally isolated (`--nodiscover`, `--maxpeers 0`) during mining to prevent accidentally joining mainnet while mining a historical fork.
