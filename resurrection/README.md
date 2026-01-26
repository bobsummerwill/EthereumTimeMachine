# Ethereum Resurrection

GPU mining to extend historical chains beyond their original blocks, reducing difficulty to CPU-mineable levels.

## Current Status (Live)

**Block 1920070** | Difficulty: **2.36 TH** | Progress: **22%** (70/316 blocks) | ETA: **~8 hours**

| Block | Difficulty | Date (UTC) |
|-------|------------|------------|
| 1920000 | 59.37 TH | 2026-01-15 |
| 1920020 | 22.94 TH | 2026-01-22 |
| 1920040 | 8.53 TH | 2026-01-25 |
| 1920060 | 3.34 TH | 2026-01-26 |
| **1920070** | **2.36 TH** | **2026-01-26** |
| ~1920320 | 10 MH | ~2026-01-27 (CPU-mineable) |

Mining is accelerating rapidly as difficulty drops. See `generated-files/resurrection_chart.png` for visualization.

## Revival Options

|  | Homestead | Frontier |
|--|-----------|----------|
| Geth | v1.3.6 | v1.0.2 |
| Block | 1,919,999+ | 1,149,999+ |
| Start difficulty | 62.38 TH | ~20.5 TH |
| Target difficulty | ~10 MH | ~50 MH |
| Reduction/block | ~4.83% | ~0.049% |
| Blocks needed | ~316 | ~26,500 |
| GPUs | 8x RTX 3090 (~846 MH/s) | 8x RTX 3090 (~846 MH/s) |
| Time | ~18 days | **~19 months** |
| Cost | ~$525 | **~$17,000** |

**Recommendation**: Start with Homestead. Frontier requires ~80x more blocks due to its simpler difficulty algorithm that only reduces by 1/2048 per block regardless of timestamp gap.

## How It Works

### Difficulty Algorithms

**Homestead (EIP-2)**:
```
adjustment = max(1 - (timestamp_delta // 10), -99)
new_difficulty = parent_difficulty + (parent_difficulty // 2048) * adjustment
```
With 1000s gaps: `floor(1000/10) = 100`, so `adjustment = max(1-100, -99) = -99`, reducing difficulty by ~4.83% per block. This is the minimum gap that achieves maximum reduction.

**Frontier**:
```
if timestamp_delta >= 13:
    new_difficulty = parent_difficulty - (parent_difficulty // 2048)
```
Only reduces by 1/2048 (~0.049%) per block regardless of timestamp gap.

### Natural Difficulty Adjustment

With 8x RTX 3090 GPUs (~846 MH/s) mining at 62.38 TH difficulty, blocks take **~20 hours** to find. This creates natural timestamp gaps of ~72,000 seconds between blocks.

**Homestead**: The formula `max(1 - (timestamp_delta // 10), -99)` with 72,000s gaps gives:
- `adjustment = max(1 - 7200, -99) = -99`
- This is the **maximum possible reduction** of ~4.83% per block
- No artificial timestamp manipulation needed - the natural mining rate maxes out the difficulty reduction

**Frontier**: Any gap ≥13s gives the fixed 0.049% reduction per block, so the slow mining rate easily qualifies.

### Auto-Stop & P2P Handoff

Scripts auto-stop when difficulty reaches target threshold, then restart geth with P2P enabled for chaindata sync to other machines for CPU mining.

## Directory Structure

```
resurrection/
├── mining-script.sh       # GPU mining script (--era homestead|frontier)
├── deploy-vast.sh         # Vast.ai deployment CLI (search, create, deploy, ssh, logs)
├── STATUS.md              # Detailed mining status and commands
├── requirements.txt       # Python dependencies (vastai)
├── .venv/                 # Python virtual environment
└── generated-files/       # (gitignored)
    ├── resurrection_chart.png/svg  # Difficulty curve visualization
    ├── resurrection_table.png/svg  # Mining progress table
    ├── miner-address.txt
    ├── miner-private-key.hex
    ├── miner-password.txt
    └── data/              # Nodekeys for P2P identity
```

## Deployment

### Using deploy-vast.sh (Recommended)

```bash
# Prerequisites
pip install vastai
vastai set api-key YOUR_API_KEY

# 1. Search for instances
./deploy-vast.sh search

# 2. Create instance
./deploy-vast.sh create OFFER_ID

# 3. Deploy mining (default: homestead)
./deploy-vast.sh deploy INSTANCE_ID homestead
# Or for Frontier:
./deploy-vast.sh deploy INSTANCE_ID frontier

# 4. Monitor
./deploy-vast.sh logs INSTANCE_ID
./deploy-vast.sh status INSTANCE_ID
./deploy-vast.sh ssh INSTANCE_ID

# 5. Cleanup
./deploy-vast.sh destroy INSTANCE_ID
```

### Manual Deployment

```bash
# Upload script
rsync -avzP mining-script.sh root@sshX.vast.ai:/root/ -e "ssh -p PORT"

# Run
ssh -p PORT root@sshX.vast.ai "nohup /root/mining-script.sh --era homestead > mining-output.log 2>&1 &"

# Monitor
ssh -p PORT root@sshX.vast.ai "tail -f /root/mining.log"
```

## Homestead Difficulty Progression

With 1 machine (8x RTX 3090 @ 846 MH/s):

| Block | Difficulty | Block Time | Cumulative |
|-------|------------|------------|------------|
| 1 | 62.4 TH | 20.5 hours | 20.5 hours |
| 50 | 5.5 TH | 1.8 hours | 210 hours |
| 100 | 490 GH | 9.7 min | 366 hours |
| 150 | 43 GH | 51 sec | 404 hours |
| 200 | 3.8 GH | 4.5 sec | 414 hours |
| ~316 | 10 MH | instant | ~421 hours |

Total: ~421 hours (~18 days). Scale linearly with more machines.

## Frontier Difficulty Progression

With 1 machine (8x RTX 3090 @ 846 MH/s):

| Block | Difficulty | Block Time | Cumulative |
|-------|------------|------------|------------|
| 1 | 20.5 TH | 6.7 hours | 0 days |
| 100 | 19.5 TH | 6.4 hours | 27 days |
| 500 | 16.1 TH | 5.3 hours | 124 days |
| 1,000 | 12.6 TH | 4.1 hours | 222 days |
| 2,000 | 7.7 TH | 2.5 hours | 358 days |
| 5,000 | 1.8 TH | 35 min | 524 days |
| 10,000 | 155 GH | 3.1 min | 570 days |
| 20,000 | 1.2 GH | 1.4 sec | 574 days |
| ~26,500 | 50 MH | instant | ~574 days |

Total: ~574 days (~19 months) at ~$1.25/hr = ~$17,000. Scale linearly with more machines.

**Why so slow?** Frontier's difficulty only drops by 1/2048 (~0.049%) per block, regardless of timestamp gap. The first 5,000 blocks consume 91% of total mining time.

## GPU Mining Details

The mining script uses **ethminer with CUDA** for NVIDIA GPUs. CUDA provides:
- Fast DAG generation across all GPUs (~1 second per GPU)
- No multi-GPU serialization issues (unlike OpenCL)
- Optimized for RTX 3090 (Compute 8.6)

Expected hashrates:
- 8x RTX 3090: ~846 MH/s total (~106 MH/s per GPU)

## Troubleshooting

### Work Expiration Bug (geth 1.0.2 and 1.3.6 Remote Mining)

**Applies to**: Both Frontier (geth 1.0.2) and Homestead (geth 1.3.6) mining

**Symptom**: ethminer runs for hours with `A0` (zero accepted solutions), even though hashrate is normal. Geth logs show:
```
Work was submitted for <hash> but no pending work found
```

**Root Cause**: Both geth 1.0.2 and 1.3.6 have identical `remote_agent.go` code that expires pending work after 84 seconds (7 × 12s block time). This was fine in 2015-2016 when thousands of miners produced new blocks every ~15 seconds, constantly refreshing work. In our resurrection scenario, **we are the only miners** - no new blocks means no work refresh.

At high difficulty (e.g., 56.5 TH for Homestead, 20.5 TH for Frontier) with ~2.5 GH/s hashrate, finding a solution takes hours. By then, geth has deleted the work from its internal map and rejects valid solutions.

**Technical Details**:
```go
// miner/remote_agent.go - maintainLoop() deletes work older than 84 seconds:
if time.Since(work.createdAt) > 7*(12*time.Second) {
    delete(a.work, hash)
}

// miner/worker.go - commitNewWork() sets createdAt:
work := &Work{
    createdAt: time.Now(),  // Only set when NEW work is created
    ...
}
```

The key insight: `createdAt` is only set when `commitNewWork()` is called, which happens when:
1. A new block is added to the chain (ChainHeadEvent)
2. Mining completes successfully
3. Miner starts

Since we're stuck waiting for a block with no external blocks arriving, `commitNewWork()` is never called again.

**Solution**: The `start_work_refresher()` function in `mining-script.sh` runs a background loop that cycles `miner_stop`/`miner_start` via RPC every 60 seconds:

```bash
while true; do
  sleep 60
  curl -X POST --data '{"method":"miner_stop",...}' http://127.0.0.1:8545
  sleep 1
  curl -X POST --data '{"method":"miner_start",...}' http://127.0.0.1:8545
done
```

This triggers `commitNewWork()` which creates a fresh Work struct with a new `createdAt` timestamp, preventing the 84-second expiration. The work hash changes each cycle, but ethminer handles this gracefully since nonce search is random anyway.

**Verification**:
```bash
# Check work-refresher is running
pgrep -f work-refresher

# Check work-refresher log
tail /root/work-refresher.log

# Verify work hash changes after miner restart
curl -X POST --data '{"method":"eth_getWork",...}' http://127.0.0.1:8545
```

### P2P Sync: "No peers connected"

The mining script syncs chaindata from a chain-of-geths node before mining. If it reports no peers:

1. **Check the source node is running**:
   ```bash
   # On your chain-of-geths host (e.g., AWS EC2)
   docker ps | grep geth
   ```

2. **Check network connectivity from Vast.ai**:
   ```bash
   # Test TCP connection to the P2P port (Vast.ai sync node)
   nc -zv 1.208.108.242 46762  # Sync node TCP port
   ```

3. **Check sync node is running**:
   - The sync node must be running geth with the correct chaindata
   - Verify with: `curl -s http://<sync-node-ip>:8545 -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'`

### Frontier: "geth v1.0.2 binary not found"

Geth v1.0.2 has no official prebuilt Linux binary. The deploy script automatically builds it locally using Docker and uploads it to Vast.ai.

If this fails, ensure:
1. Docker is installed and running on your local machine
2. The `ethereumtimemachine/geth:v1.0.2` image exists (built by `chain-of-geths/build-images.sh`)

**Manual fix** (if automatic build fails):
```bash
# Build the image first (if needed)
cd chain-of-geths && ONLY_VERSION=v1.0.2 ./build-images.sh

# Extract the binary
docker run --rm --entrypoint /bin/sh -v /tmp:/out \
  ethereumtimemachine/geth:v1.0.2 \
  -c 'cp /usr/local/bin/geth /out/geth-v1.0.2'

# Upload to Vast.ai instance
scp -P PORT /tmp/geth-v1.0.2 root@sshX.vast.ai:/root/geth
```

### Mining stalled / ethminer died

The script auto-restarts ethminer if it crashes. Check logs:
```bash
tail -100 /root/ethminer.log
tail -100 /root/geth.log
```

Common issues:
- **GPU memory errors**: Check GPU health with `nvidia-smi`
- **CUDA errors**: Ensure CUDA toolkit is installed (the nvidia/cuda Docker image includes it)

## Key Configuration (Important for AI Assistants)

This section documents critical configuration values that must stay synchronized across files. **If you modify any of these, update all related locations.**

### Sync Node Identity (Vast.ai)

The sync node on Vast.ai has a fixed identity that client bundles must connect to. This was deployed separately from the deterministic key generation.

| Value | Location | Description |
|-------|----------|-------------|
| Nodekey | `91c01e9b759b0ebcebfdf873cadbe73505d9bf391661f3358f6e6a71445159bb` | Private P2P identity |
| Enode pubkey | `ac449332fe8d9114ff453693360bebe11e4e58cb475735276b1ea60abe7d46c246cf2ec6de9d5cd24f613868a4d2328b9f230a3f797fa48e2c80791d3b24e6a7` | Public key derived from nodekey |
| IP:Port | `1.208.108.242:46762` | Vast.ai instance 29980870 |
| Full enode | `enode://ac449332...@1.208.108.242:46762` | For static-nodes.json |

**Files that must use this enode:**
- `generate-keys.sh` - Hardcodes the nodekey and pubkey (lines ~260-262)
- `generated-files/nodes/sync-node/nodekey` - Must contain the nodekey
- `generate-geth-*.sh` scripts - Read nodekey and derive pubkey via Docker

**Why hardcoded?** The sync node was deployed before `generate-keys.sh` added deterministic key generation. The deployed node's identity cannot change without redeploying. Client bundles must connect to this specific enode.

### Miner Account

The miner address is embedded in existing chaindata and cannot be changed:

| Value | Description |
|-------|-------------|
| Private key | `1ef4d35813260e866883e70025a91a81d9c0f4b476868a5adcd80868a39363f5` |
| Address | `0x3ca943ef871bea7d0dfa34bff047b0e82be441ef` |
| Password | `dev` |

**Files:** `generate-keys.sh` (lines ~210-212), `generated-files/miner-account/`

### Bundle Generator Scripts

The client bundle generators (`generate-geth-*.sh`) share common logic:

1. Read nodekey from `generated-files/nodes/sync-node/nodekey`
2. Derive enode pubkey using Docker (ethereum/client-go:v1.16.7)
3. Create static-nodes.json with the full enode URL
4. Package with appropriate geth binary

**Common issues:**
- **Wrong pubkey**: If the nodekey file contains wrong value, bundles will have wrong enode
- **Duplicate pubkey**: The Docker derivation can output twice; use `tail -1` to get last match
- **IP/Port mismatch**: Must use Vast.ai's mapped port (46762), not internal port (30303)

### Checking Configuration Consistency

```bash
# Verify nodekey file matches expected value
cat generated-files/nodes/sync-node/nodekey
# Should output: 91c01e9b759b0ebcebfdf873cadbe73505d9bf391661f3358f6e6a71445159bb

# Regenerate bundles after any key changes
./generate-geth-1.4.0-macos.sh
./generate-geth-1.4.18-macos.sh
./generate-geth-1.3.6-windows.sh

# Verify enode in generated bundle
tar -xzf generated-files/geth-macos-v1.4.18.tar.gz -O geth-v1.4.18-macos-resurrection/data/static-nodes.json
# Should contain: enode://ac449332fe8d9114...@1.208.108.242:46762
```
